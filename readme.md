# Receive-based Architecture

```
                      [ External Sources / VA / APIs ]
                                      │
                                      ▼
                        [ Kong API Gateway (Proxy) ]
                                      │
                                      ▼
                         [ Ingestion / ETL Engine ]
                                (n8n / Worker)
                                      │
                   ┌──────────────────┴──────────────────┐
                   ▼                                     ▼
        [ Path A: Urgent Path ]               [ Path B: Raw Storage ]
        (Urgent / Alarm Flag)                 (All Ingested Data)
                   │                                     │
                   ▼                                     ▼
          [ Message Broker ]                     [ Raw Data Store ]
       (Redis Streams / Kafka)               (MinIO, MongoDB, S3, Lake)
                   │                                     │
                   ▼                                     ▼
        [ Alert / Action Consumer ]             [ Batch / Analytics ETL ]
      (Notification API, Webhooks)           (Curated Zone / Dashboards)

```

---

### Component & Tool Selection

| Stage                      | Recommended Tool                               | Role & Responsibility                                                                                       |
| -------------------------- | ---------------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| **Entry Point**            | **Kong Gateway**                               | Validates incoming API keys/tokens, applies rate limiting, and forwards traffic to the ingestion layer.     |
| **Ingestion & Classifier** | **n8n** _(or lightweight Go / Python service)_ | Pulls or accepts the data, normalizes timestamps, evaluates priority rules, and bifurcates the flow.        |
| **Urgent Message Broker**  | **Redis Streams** _(or Redpanda / Kafka)_      | Decouples alerts from ingestion. Provides microsecond queuing with consumer groups and acknowledgments.     |
| **Urgent Consumer**        | **Worker Script / n8n Webhook**                | Listens to the broker queue, formats messages, and triggers paging/alerts (Slack, SMS, downstream webhook). |
| **Raw Data Zone**          | **MongoDB / MinIO / PostgreSQL**               | Stores the complete, unmutated JSON payload for compliance, cold storage, and batch analytics.              |

---

### Detailed Step-by-Step Flow

**1. Gateway Routing & Ingestion**

- The external provider or Virtual Assistant sends a payload through Kong via a route like `/api/v1/telemetry`.
- Kong enforces authentication (via `key-auth` or `jwt` plugin) and forwards the request to your ingestion service (e.g., an n8n Webhook node or an internal microservice).

**2. In-Flight Classification & Priority Detection**

- The ingestion logic inspects the payload headers or body fields:

```json
{
  "event_id": "evt-10928",
  "timestamp": "2026-09-09T01:50:00Z",
  "severity": "CRITICAL",
  "reading": 104.5,
  "source": "sensor-node-04"
}
```

- A conditional check evaluates if `severity in ["CRITICAL", "ALARM", "HIGH"]` or if thresholds are breached.

**3. Dual-Path Split (Speed vs. Storage)**

- **Path A (Urgent Path):**
- The ingestion engine immediately publishes the event to the broker:
- _If using Redis Streams:_ Executes `XADD stream:urgent * event_id evt-10928 severity CRITICAL ...`
- _If using Kafka:_ Emits to the `events.urgent` topic.

- The consumer group picks up the entry in sub-millisecond time, bypassing storage queues, and triggers downstream webhooks, push notifications, or command center alerts.

- **Path B (Raw Storage Path):**
- The full unmodified payload is written asynchronously into the raw repository (e.g., MongoDB `raw_events` collection or MinIO as an object) with an ingestion timestamp.
- Writing to storage does not block or delay the urgent message delivery.

---

### Tool Decision Matrix: Redis Streams vs. Kafka

- **Use Redis Streams** if:
- Ingestion volume is under 20,000–50,000 messages/second.
- You already run Redis in your stack.
- You want minimal CPU/RAM overhead and simple operational maintenance (no KRaft/ZooKeeper).

- **Use Kafka (or Redpanda)** if:
- Multiple independent engineering teams/services need to read the same stream and maintain distinct offsets.
- You need to replay historical messages days or weeks later from disk.
- Throughput exceeds tens of thousands of continuous events per second.

# Pull-Based Ingestion Architecture

When pulling (polling) third-party APIs instead of receiving webhooks, the API Gateway is bypassed at the front. Instead, a **Scheduler/Worker** initiates outbound calls, manages pagination and state (watermarking), dumps raw data, and scans for urgent records to publish immediately.

```
                  ┌────────────────────────────────────────┐
                  │          Scheduler / State Store       │
                  │   (Cron / n8n Schedule / Redis State)  │
                  └───────────────────┬────────────────────┘
                                      │ Triggers job with "last_seen_timestamp"
                                      ▼
                        [ Polling & Ingestion Worker ]
                         (n8n / Python / Go Worker)
                                      │
                 Outbound GET         │ Handles OAuth2,
              with pagination params  │ rate limits & retries
                                      ▼
                          [ External Target API ]
                                      │
                                      ▼ (Returns batch JSON)
                        [ In-Flight Split Engine ]
                   ┌──────────────────┴──────────────────┐
                   ▼                                     ▼
        [ Path A: Urgent Detection ]          [ Path B: Raw Zone ]
        (Filter: status/threshold)            (Full Unmodified Batch)
                   │                                     │
                   ▼                                     ▼
          [ Message Broker ]                     [ Raw Data Store ]
       (Redis Streams / Kafka)               (MinIO, MongoDB, S3, Lake)
                   │                                     │
                   ▼                                     ▼
        [ Alert / Action Consumer ]             [ Batch / Analytics ETL ]
      (Downstream Notification / UI)         (Curated Tables / Reporting)

```

---

### Key Components & Tools

| Component                    | Recommended Tool                                   | Role & Responsibility                                                                                                              |
| ---------------------------- | -------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| **Scheduler & Orchestrator** | **n8n** _(or Temporal / Celery / Cron)_            | Triggers the pull task on a timer (e.g., every 30s, 5m, or 1h) and coordinates pagination.                                         |
| **State / Watermark Store**  | **Redis** or **PostgreSQL**                        | Stores cursor state (e.g., `last_updated_at`, `max_id`, or `next_page_token`) so you only fetch new or updated data (delta pulls). |
| **API Client & Transformer** | **n8n HTTP Node** _(or Python `httpx`/`requests`)_ | Manages OAuth2 token refresh, API rate limits, backoff on HTTP 429/500, and JSON parsing.                                          |
| **Urgent Message Broker**    | **Redis Streams** _(or Kafka)_                     | Immediate queue for critical items detected inside the polled batch.                                                               |
| **Raw Data Zone**            | **MinIO / S3 / MongoDB**                           | Stores raw JSON responses by date/batch ID before schema normalization.                                                            |

---

### Step-by-Step Polling Flow

**1. Retrieve High-Water Mark (State Management)**

- Before calling the third-party API, the worker retrieves the last successful sync point from the state store (e.g., `last_sync_timestamp = 2026-09-09T01:00:00Z`).
- This ensures you only request delta changes and avoid re-processing duplicate records.

**2. Execute Outbound Fetch (with Pagination & Rate Limiting)**

- The worker calls the target API:

```http
GET /v1/records?updated_since=2026-09-09T01:00:00Z&limit=100
Authorization: Bearer <token>

```

- If the API paginates via cursor or page numbers, the worker loops until all pages are retrieved, respecting upstream rate limits (`429 Too Many Requests` backoff headers).

**3. Dual-Path Split (Immediate Branching)**
Once each page/batch arrives in memory:

- **Path A (Scan for Urgent Records):**
- Loop through items in memory and check conditions (e.g., `record.status === "CRITICAL"` or `record.metric > threshold`).
- If found, immediately publish to the **Redis Stream** or alert endpoint:

```bash
XADD stream:urgent * event_id rec_987 source external_vendor severity CRITICAL

```

- Downstream alert consumers react instantly without waiting for the entire batch ETL to finish.

- **Path B (Raw Ingestion):**
- Write the complete payload unmodified into the raw store (e.g., as `raw_vendor_20260909_0100.json` in MinIO/S3 or an unindexed document in MongoDB).
- Update the `last_sync_timestamp` in your state store only after the raw batch successfully commits.

---

### Managing Common Polling Pitfalls

- **API Token Expiry:** External APIs often use OAuth2 with 1-hour access tokens. Use an HTTP client/node that automatically checks token expiration and requests a new token via `refresh_token` before pulling.
- **API Rate Limits:** Hard-code a concurrency limiter or sleep interval (e.g., 200ms between page requests) to stay within vendor limits.
- **Network Failures / Deduplication:** If a poll fails mid-pagination, ensure your ingestion pipeline applies an idempotency key (such as `external_id` or hashing the payload) when saving to prevent duplicate downstream alerts.

### Side-by-Side Tool Comparison

| Pipeline Stage                | **Approach 1: Low-Code / Orchestrator Stack (n8n)**             | **Approach 2: Custom Code / Microservices Stack (Python / Go)**             |
| ----------------------------- | --------------------------------------------------------------- | --------------------------------------------------------------------------- |
| **Scheduler**                 | **n8n Schedule Trigger** (Interval/Cron node)                   | **Linux Cron**, **APScheduler**, or **Celery Beat**                         |
| **Ingestion & Fetch Engine**  | **n8n HTTP Request Node** (built-in pagination, OAuth2 refresh) | **Python (`httpx` / `requests`)** or **Go (`net/http`)**                    |
| **State / Watermark Store**   | **n8n Static Workflow Data** (`$getWorkflowStaticData`)         | **Redis** (`GET`/`SET` keys) or **PostgreSQL** table                        |
| **ETL & Data Shaping**        | **n8n Code Node** (inline JS) + **Item Lists Node**             | **Pydantic**, **Pandas**, or native Go structs                              |
| **Fast Path (Urgent Broker)** | **n8n Redis Node** (`XADD`) or **Kafka Node**                   | **`redis-py`** (`xadd`) or **`confluent-kafka`** / **`segmentio/kafka-go`** |
| **Raw Storage Zone**          | **n8n MongoDB Node**, **Postgres Node**, or **S3 Node**         | **`motor` / `pymongo**`, **`asyncpg`**, or **`boto3` / MinIO SDK\*\*        |
| **Alert Delivery**            | **n8n Pre-built Nodes** (Slack, Discord, Email, Webhook)        | Downstream consumer worker script sending webhooks/SMS                      |
| **Execution Observability**   | Built-in n8n GUI execution log, failed run replay               | Prometheus metrics, OpenTelemetry, Grafana, Loki/ELK logs                   |

---

### Architecture 1: The n8n Workflow Approach

This approach places the entire lifecycle inside a single visual container.

```
[n8n Schedule Trigger]
         │
         ▼
[n8n Static Memory] ──► Reads last processed timestamp / watermark
         │
         ▼
[n8n HTTP Request]  ──► Pulls external API with auto-pagination & OAuth2
         │
         ▼
[n8n If / Switch]
    ├── True (Urgent) ──► [n8n Redis Node] ──► Pushes XADD stream to alert consumers
    │
    └── All Records  ──► [n8n MongoDB/S3 Node] ──► Dumps raw JSON payloads

```

- **Best When:** You want zero deployment friction, visual step-by-step debugging, built-in credential management, and quick adjustments without maintaining Docker microservice CI/CD pipelines.
- **Limitation:** Resource-heavy if batches scale into tens of thousands of records per pull, as large JSON arrays live directly in Node.js memory.

---

### Architecture 2: The Custom Code / Microservice Approach

This approach decouples ingestion into lightweight, containerized daemon services.

```
[Cron / APScheduler / Celery Beat]
         │
         ▼
[Python/Go Worker] ──► Reads cursor/timestamp from Redis key
         │
         ├── Calls vendor API via httpx (async / streaming)
         ├── Validates schema via Pydantic / Go struct
         │
         ├── In-flight check: if severity == "CRITICAL"
         │         └──► redis.xadd("stream:urgent", payload)
         │
         └── Async bulk write ──► pymongo / MinIO object store

```

- **Best When:** You require sub-second polling intervals, high data density (tens of megabytes of nested JSON per cycle), custom binary/gRPC protocols, or strict unit/integration testing suites.
- **Limitation:** Higher operational burden—you must write your own backoff/retry mechanisms, OAuth2 token lifecycle managers, and monitoring/alerting infrastructure.

### Architecture Summary: Managing Zones in MinIO

Moving data through **Raw (Bronze)**, **Curated (Silver)**, and **Publish (Gold)** zones creates a structured **Medallion Lakehouse architecture** using MinIO for object storage paired with an execution engine.

---

### 1. The Three Data Zones in MinIO

| Zone                 | MinIO Bucket         | Data Format                             | Purpose                                                                                          | Lifecycle / Retention                         |
| -------------------- | -------------------- | --------------------------------------- | ------------------------------------------------------------------------------------------------ | --------------------------------------------- |
| **Raw (Bronze)**     | `s3://lake-raw/`     | Compressed JSON / JSONL (`.json.gz`)    | Immutable, byte-for-byte copy of polled API responses. Used for auditing and full re-processing. | Auto-expire or archive after 90–365 days.     |
| **Curated (Silver)** | `s3://lake-curated/` | Snappy-compressed **Parquet**           | Cleaned, deduplicated, schema-enforced, and date-partitioned data. The single source of truth.   | Permanent / long-term storage.                |
| **Publish (Gold)**   | `s3://lake-publish/` | Aggregated **Parquet** _(or DB tables)_ | Business metrics, daily rollups, and reporting datasets optimized for fast analytical queries.   | Retained per business reporting requirements. |

---

### 2. Transition Engine: What Runs the ETL?

MinIO only **stores** the files—it does not transform them. A compute engine reads from one bucket, processes the data, and writes to the next:

```
[ Ingestion (n8n) ]
        │
        ▼
 🪣 lake-raw (Raw JSON)
        │
        ▼  ◄── ETL Step 1: DuckDB / Polars (Casts types, cleans, converts to Parquet)
 🪣 lake-curated (Clean Parquet)
        │
        ▼  ◄── ETL Step 2: DuckDB (Aggregates, rollups, joins)
 🪣 lake-publish (Gold Parquet)
        │
        └──► Optional: Push to PostgreSQL / Redis (for sub-50ms API access by your VA)

```

---

### 3. Recommended Tools for the Transitions

- **DuckDB (Best for SQL & Speed):**
- Reads JSON and Parquet directly to/from MinIO over the S3 protocol (`httpfs` extension) using simple `COPY (...) TO 's3://...'` SQL statements.
- In-process execution with zero cluster overhead, low RAM consumption, and native support for partitioned Parquet output.

- **Polars / Python (Best for Complex Logic):**
- Vectorized DataFrames using `pl.read_ndjson()` and `df.write_parquet()`.
- Ideal when payloads have unpredictable nesting, need complex regex cleaning, or require custom programmatic validations before saving to Curated.

- **Orchestration (n8n or Cron):**
- Triggers the transformation task (via command execution, Docker run, or webhook) immediately after a raw ingestion batch completes or on a scheduled hourly/daily cadence.

---

### 4. Operational Best Practice

- Keep **Raw** strictly append-only (enable Object Locking / WORM if compliance is needed).
- Use **Curated** for ad-hoc analytical queries and machine learning training.
- If your **Virtual Assistant or operational frontend** needs data from the **Publish** layer, mirror the final Gold summary into an indexed operational store (**PostgreSQL**, **MongoDB**, or **Redis**) so user-facing queries remain fast without scanning Parquet files over object storage.

**Yes, Kong Gateway should be used at the front of your published layer, but as the secure access proxy, not as the data provider.**

Kong sits at the perimeter to protect, authenticate, cache, and rate-limit requests coming from external clients, web apps, or your Virtual Assistant (VA). However, **Kong cannot read Parquet files or execute queries directly against MinIO**.

---

### The Complete Serving Architecture

A lightweight **Serving API** sits between Kong and your published storage to translate incoming REST requests into optimized queries against your Gold/Publish zone:

```
[ External Consumers / VA / Web Apps ]
                 │
                 ▼ (Calls: GET /api/v1/metrics/daily)
      [ Kong API Gateway ]  ◄── Enforces API Key, JWT, Rate Limiting, & Proxy Caching
                 │
                 ▼ (Proxies to internal service)
     [ Data Serving Microservice ]
   (e.g., FastAPI / Go / PostgREST)
                 │
        ┌────────┴──────────────────────────┐
        ▼                                   ▼
 [ Operational DB ]                 [ MinIO: lake-publish ]
(Postgres / MongoDB)                  (Gold Parquet files)
(Best for sub-20ms point lookups)    (Best for large analytical slices)

```

---

### Why Place Kong in Front of the Published Data?

Using Kong as the single entry point to published data provides several operational benefits:

- **Authentication & Access Control:** Restrict consumer access using plugins like `key-auth`, `jwt`, or `oauth2` without embedding authentication logic inside your data serving code.
- **Proxy Caching (`proxy-cache` plugin):** If multiple users or VA sessions request identical aggregate reports (e.g., "today's incident summary"), Kong serves the cached response directly from memory, preventing repetitive database or S3 hits.
- **Rate Limiting (`rate-limiting` plugin):** Prevents external consumers or bot scripts from running intensive analytical queries that could exhaust backend compute resources.
- **API Versioning & Path Rewriting:** Map clean, public routes (e.g., `/v1/reports/incidents`) to internal microservices without exposing internal network paths or hostnames.

---

### How to Bridge Kong to Your Gold Data

To expose your Publish layer to Kong, choose one of two serving patterns:

#### Pattern A: Direct REST over Database (Fastest for VA & App Lookups)

Sync the Gold aggregates produced during ETL directly into a serving database (e.g., **PostgreSQL** or **MongoDB**).

1. Deploy an auto-REST generator (like **PostgREST** for Postgres) or a lightweight **Go / FastAPI** microservice.
2. Route Kong directly to that service:

- **Kong Route:** `/api/v1/reports` $\rightarrow$ **Upstream Service:** `http://postgrest:3000/daily_summary`

#### Pattern B: Direct SQL Query Engine over MinIO Parquet (Best for Analytics)

If Gold data remains purely as Parquet files in MinIO:

1. Run a lightweight query engine like **DuckDB** inside a small Python/Go container (or **Trino** for multi-node deployments).
2. The service exposes a REST endpoint: when Kong proxies a request, the service runs a DuckDB query over the Parquet files in `s3://lake-publish/` and returns JSON.

---

### Ingestion vs. Publishing: Kong's Dual Role

```
[ INGESTION FLOW ]
External Call / VA ──► Kong Gateway ──► n8n Poller/Ingestion ──► MinIO (Raw)

[ PUBLISHING FLOW ]
Consumer / Dashboard ──► Kong Gateway ──► Serving API ──► MinIO (Publish) / Postgres

```

Reusing the same Kong Gateway instance simplifies governance: all inbound traffic (ingestion webhooks) and outbound consumption (published data endpoints) pass through the same security, rate-limiting, and auditing layer.

---

# Overall Common Data Environment (CDE) Master Architecture

The Common Data Environment (CDE) unifies perimeter ingress, dual-path real-time classification, a Medallion Lakehouse on MinIO, and secure egress serving through a single edge layer.

```
 ════════════════════════════════════════════════════════════════════════════════════════════════════════
                                  COMMON DATA ENVIRONMENT (CDE)
 ════════════════════════════════════════════════════════════════════════════════════════════════════════

  [ INBOUND SOURCES ]
  ┌─────────────────────────┐       ┌────────────────────────┐
  │ Push Webhooks / Sensors │       │ Polled Third-Party APIs│
  └────────────┬────────────┘       └───────────▲────────────┘
               │                                │
               ▼ (Port 8088)                    │ (Outbound GET, OAuth2, Pagination)
  ┌─────────────────────────┐       ┌───────────┴────────────┐
  │   KONG API GATEWAY      │       │ Scheduler & State Store│
  │ (Auth, RateLimit, CORS) │       │ (Redis / Postgres KV)  │
  └────────────┬────────────┘       └───────────┬────────────┘
               │                                │
               ▼                                ▼
  ┌──────────────────────────────────────────────────────────┐
  │              INGESTION & IN-FLIGHT ENGINE                │
  │             (n8n Orchestrator / Python Worker)           │
  └────────────┬────────────────────────────────┬────────────┘
               │                                │
    [ PATH A: URGENT LANE ]          [ PATH B: RAW PERSISTENCE ]
    (Severity: ALARM / CRITICAL)     (100% Unmodified Payloads)
               │                                │
               ▼                                ▼
  ┌─────────────────────────┐       ┌────────────────────────┐
  │      REDIS STREAMS      │       │   MINIO OBJECT STORE   │
  │     (Message Broker)    │       │     🪣 lake-raw        │
  └────────────┬────────────┘       │  (Bronze: .json.gz)    │
               │                    └───────────┬────────────┘
               ▼                                │
  ┌─────────────────────────┐                   ▼ (ETL Step 1: Clean & Validate)
  │ Alert & Action Worker   │       ┌────────────────────────┐
  │ (Slack, SMS, PagerDuty) │       │ DuckDB / Polars Engine │
  └─────────────────────────┘       └───────────┬────────────┘
                                                │
                                                ▼
                                    ┌────────────────────────┐
                                    │   MINIO OBJECT STORE   │
                                    │    🪣 lake-curated     │
                                    │ (Silver: Snappy Parquet│
                                    └───────────┬────────────┘
                                                │
                                                ▼ (ETL Step 2: Aggregations & Rollups)
                                    ┌────────────────────────┐
                                    │ DuckDB / Polars Engine │
                                    └───────────┬────────────┘
                                                │
                     ┌──────────────────────────┴──────────────────────────┐
                     ▼                                                     ▼
     ┌───────────────────────────────┐                     ┌───────────────────────────────┐
     │      MINIO OBJECT STORE       │                     │      OPERATIONAL STORE        │
     │       🪣 lake-publish         │  (Daily Rollups)    │   PostgreSQL / Redis Cache    │
     │     (Gold: Parquet Lake)      ├────────────────────►│  (Sub-20ms Index Point Read)  │
     └───────────────┬───────────────┘                     └───────────────┬───────────────┘
                     │                                                     │
                     ▼ (Complex Analytical SQL)                            ▼ (CRUD / Metrics REST)
     ┌───────────────────────────────┐                     ┌───────────────────────────────┐
     │ DuckDB Serving Container      │                     │ PostgREST / FastAPI Service   │
     └───────────────┬───────────────┘                     └───────────────┬───────────────┘
                     │                                                     │
                     └──────────────────────────┬──────────────────────────┘
                                                │
                                                ▼ (Internal Upstream Calls)
                                   ┌─────────────────────────┐
                                   │   KONG API GATEWAY      │
                                   │ (Proxy-Cache, Auth, ACL)│
                                   └────────────┬────────────┘
                                                │
                                                ▼ (Port 8088 / HTTPS 8443)
                                 [ OUTBOUND CONSUMPTION ]
                                 ├── Virtual Assistant (VA)
                                 ├── Operations Dashboard
                                 └── External Partner APIs
```

---

### End-to-End Component Matrix

| Stage | Primary Technology | Responsibility | SLA / Latency Target |
| :--- | :--- | :--- | :--- |
| **Ingress Perimeter** | **Kong Gateway OSS 3.9** | API keys (`key-auth`), rate limiting, IP whitelisting, request logging | $< 2\text{ ms}$ routing overhead |
| **Ingestion Engine** | **n8n / Python (`httpx`)** | Push webhook receiver, outbound polling, state/cursor tracking, bifurcation | Real-time / Scheduled |
| **Fast Path** | **Redis Streams** (`XADD`) | Microsecond message pub/sub decoupled from database I/O | $< 5\text{ ms}$ notification dispatch |
| **Raw Storage (Bronze)** | **MinIO (`lake-raw`)** | Immutable payload backup (compressed JSONL), retention 90–365d | Append-only archival |
| **Compute / Transformation** | **DuckDB / Polars** | Reads Bronze $\rightarrow$ Deduplicates $\rightarrow$ Enforces Schema $\rightarrow$ Writes Silver/Gold Parquet | Batch / Micro-batch (1m to 1h) |
| **Curated Store (Silver)** | **MinIO (`lake-curated`)** | Single source of truth, date-partitioned Parquet | Cold/warm analytical access |
| **Publish Store (Gold)** | **MinIO (`lake-publish`)** & **PostgreSQL** | Business aggregations, pre-calculated KPIs, operational views | Dual storage (Parquet + Relational) |
| **Serving Layer** | **FastAPI / PostgREST** | RESTful access to Postgres and DuckDB SQL execution on Parquet | $10\text{–}50\text{ ms}$ query response |
| **Egress Perimeter** | **Kong Gateway OSS 3.9** | In-memory `proxy-cache`, consumer identity tokens, query rate limits | Sub-millisecond on cache hit |

---

### End-to-End Data Flow Lifecycle

1. **Ingress (Push or Pull):**
   - **Push:** External senders hit Kong Gateway at `:8088` (authenticated via `key-auth`). Kong proxies valid payloads to the Ingestion Engine (`n8n` webhook or internal worker).
   - **Pull:** The Ingestion Worker queries its state store (Redis/Postgres) for the latest cursor/watermark and polls the external vendor API, handling pagination and rate limits.
2. **In-Flight Classification & Bifurcation:**
   - **Fast Path (Alerting):** If payload contains critical thresholds or severity alarms, an event is immediately dispatched to **Redis Streams** via `XADD`. Dedicated workers consume this stream to trigger PagerDuty, Slack, or SMS in $< 5\text{ ms}$.
   - **Raw Storage:** Simultaneously, the full unmutated JSON response is written asynchronously to MinIO's `lake-raw` bucket (`.json.gz`).
3. **Medallion Lakehouse Transitions:**
   - **Bronze $\rightarrow$ Silver (Curated):** A scheduled compute job (**DuckDB** or **Polars**) reads raw JSON from `lake-raw`, cleanses data, enforces types, and writes Snappy-compressed partitioned Parquet files into `lake-curated`.
   - **Silver $\rightarrow$ Gold (Publish):** An aggregation job rollups metrics and daily summaries into `lake-publish` (Gold Parquet). High-frequency summary records are also mirrored into **PostgreSQL** for fast point lookups.
4. **Egress & Consumption:**
   - External consumers, dashboards, and Virtual Assistants send requests to Kong Gateway (`/api/v1/metrics`, `/api/v1/reports`).
   - Kong checks consumer credentials, evaluates rate limits, and checks its in-memory `proxy-cache`.
   - On cache miss, Kong proxies to the Serving Microservice (PostgREST or FastAPI), which queries PostgreSQL (sub-20ms) or queries Gold Parquet via DuckDB.

