# Common Data Environment (CDE) - Phased Development & Implementation Plan

This document outlines the step-by-step implementation plan for building, testing, and operationalizing the Common Data Environment (CDE). Each phase contains specific deliverables, Docker setup instructions, configurations, and verification procedures.

---

## Roadmap Overview

```
 ┌────────────────────────────────────────────────────────────────────────┐
 │                      CDE IMPLEMENTATION PHASES                         │
 └────────────────────────────────────────────────────────────────────────┘
     │
     ├─► Phase 1: Ingress Edge Gateway (Kong OSS 3.9 + Kong Manager)
     │
     ├─► Phase 2: Ingestion & Orchestration Layer (n8n Webhook / Poller)
     │
     ├─► Phase 3: Fast-Path Urgent Alerting Lane (Redis Streams Broker)
     │
     ├─► Phase 4: Object Storage Lakehouse (MinIO S3 - Bronze/Raw Zone)
     │
     ├─► Phase 5: Medallion Transformation Engine (DuckDB / Polars ETL)
     │
     ├─► Phase 6: Published Data Egress & Serving API (PostgREST / FastAPI)
     │
     └─► Phase 7: End-to-End Integration, Security Hardening & Monitoring
```

---

## Phase 1: Ingress Edge Gateway (Kong OSS 3.9)

### Objective
Establish the secure perimeter gateway to authenticate, throttle, and route all incoming telemetry, webhooks, and outbound data queries.

### Components
- **`kong-gateway`**: Kong OSS 3.9 listening on port `8088` (HTTP proxy) and `8443` (HTTPS proxy).
- **`kong-db`**: PostgreSQL 15 for declarative/persisted gateway state.
- **`kong-manager`**: Visual UI dashboard on port `8002`.

### Setup Instructions
1. Navigate to the `apigw` directory:
   ```bash
   cd c:\Projects\cde\apigw
   ```
2. Start the gateway stack:
   ```bash
   docker compose up -d
   ```
3. Verify running containers:
   ```bash
   docker compose ps
   ```

### Verification & Testing
- Query the Kong Admin API:
  ```bash
  curl.exe -i http://localhost:8001/
  ```
  *Expected:* HTTP `200 OK` with Kong engine version `3.9.0`.
- Open Kong Manager UI in browser: **[http://localhost:8002](http://localhost:8002)**.

---

## Phase 2: Ingestion & Orchestration Engine (n8n)

### Objective
Deploy the workflow engine responsible for receiving pushed webhooks from Kong and scheduling pull tasks for external third-party vendor APIs.

### Components
- **`cde-n8n`**: Official n8n container on port `5678` with persistent storage in `./n8n_data`.

### Setup Instructions
1. Navigate to the `n8n` directory:
   ```bash
   cd c:\Projects\cde\n8n
   ```
2. Launch the n8n container:
   ```bash
   docker compose up -d
   ```
3. Access the visual editor at **[http://localhost:5678](http://localhost:5678)** and create the primary admin credentials.

### Gateway Integration
Register n8n inside Kong to proxy inbound requests:
```bash
# 1. Register n8n upstream service
curl.exe -i -X POST http://localhost:8001/services \
  -d "name=n8n-service" \
  -d "url=http://host.docker.internal:5678"

# 2. Expose the telemetry route
curl.exe -i -X POST http://localhost:8001/services/n8n-service/routes \
  -d "name=telemetry-route" \
  -d "paths[]=/api/v1/telemetry" \
  -d "strip_path=false"
```

### Verification & Testing
1. In n8n, create a new workflow with a **Webhook Node** listening on `POST /webhook/telemetry`.
2. Post a payload to Kong Gateway:
   ```bash
   curl.exe -i -X POST http://localhost:8088/api/v1/telemetry \
     -H "Content-Type: application/json" \
     -d "{\"event_id\":\"evt-001\",\"severity\":\"INFO\",\"reading\":23.4}"
   ```
3. Confirm the execution appears in the n8n execution log.

---

## Phase 3: Fast-Path Urgent Alert Lane (Redis Streams)

### Objective
Implement sub-5ms message queuing for high-priority incidents (`CRITICAL`, `ALARM`) that bypass database writes and trigger real-time actions.

### Components
- **Redis Server**: Redis 7+ instance (using `imops-redis` on port `6379` or dedicated service).
- **Redis Stream Topic**: `stream:urgent`.
- **Alert Dispatcher**: n8n workflow or consumer script listening to consumer group `alerts-group`.

### Setup Instructions
1. Ensure Redis is accessible:
   ```bash
   docker exec -it imops-redis redis-cli ping
   # Expected: PONG
   ```
2. Create the consumer group in Redis:
   ```bash
   docker exec -it imops-redis redis-cli XGROUP CREATE stream:urgent alerts-group $ MKSTREAM
   ```

### Workflow Configuration (Inside n8n)
1. Add an **If / Switch Node** after the webhook trigger:
   - Condition: `{{ $json.body.severity }} in ["CRITICAL", "ALARM", "HIGH"]`
2. Connect the **True** branch to a **Redis Node**:
   - **Operation:** Execute Command
   - **Command:**
     ```
     XADD stream:urgent * event_id {{ $json.body.event_id }} severity {{ $json.body.severity }} message {{ $json.body.message }}
     ```
3. Create an **Alert Consumer Workflow** in n8n (or standalone Python worker):
   - Trigger: Cron / continuous loop reading `XREADGROUP GROUP alerts-group worker-1 STREAMS stream:urgent >`
   - Actions: Send Slack message, trigger SMS, or call downstream incident webhook.

### Verification & Testing
Publish an urgent payload:
```bash
curl.exe -i -X POST http://localhost:8088/api/v1/telemetry \
  -H "Content-Type: application/json" \
  -d "{\"event_id\":\"evt-999\",\"severity\":\"CRITICAL\",\"message\":\"High pressure breach\"}"
```
Verify the item in Redis:
```bash
docker exec -it imops-redis redis-cli XREVRANGE stream:urgent + - COUNT 1
```

---

## Phase 4: Lakehouse Object Storage (MinIO - Bronze/Raw Zone)

### Objective
Deploy an S3-compatible object store (MinIO) to capture full, unmutated JSON payloads with lifecycle expiration policies.

### Components
- **`cde-minio`**: MinIO Server on port `9000` (S3 API) and `9001` (Web Console).
- **Buckets**:
  - `s3://lake-raw/` (Bronze)
  - `s3://lake-curated/` (Silver)
  - `s3://lake-publish/` (Gold)

### Setup Instructions
Add the MinIO definition to the CDE stack (or create `c:\Projects\cde\minio\docker-compose.yml`):
```yaml
services:
  minio:
    image: minio/minio:latest
    container_name: cde-minio
    restart: unless-stopped
    command: server /data --console-address ":9001"
    environment:
      MINIO_ROOT_USER: cdeadmin
      MINIO_ROOT_PASSWORD: cdepassword123
    ports:
      - "9000:9000"
      - "9001:9001"
    volumes:
      - minio_data:/data
    networks:
      - cde-network

volumes:
  minio_data:
```

Launch MinIO and initialize buckets:
```bash
docker compose up -d
# Create buckets via MinIO Client (mc)
docker run --rm --network cde-network minio/mc alias set local http://cde-minio:9000 cdeadmin cdepassword123
docker run --rm --network cde-network minio/mc mb local/lake-raw local/lake-curated local/lake-publish
```

### Ingestion Integration
In n8n, connect **Path B (All Payloads)** to an **S3 / HTTP Node**:
- Target: `http://cde-minio:9000/lake-raw/{{ $now.format('yyyy/MM/dd') }}/{{ $json.event_id }}.json`

### Verification & Testing
Inspect the bucket via browser at **[http://localhost:9001](http://localhost:9001)** or query:
```bash
docker run --rm --network cde-network minio/mc ls local/lake-raw/
```

---

## Phase 5: Medallion Transformation Engine (DuckDB / Polars ETL)

### Objective
Transform raw JSON payloads into clean, schema-enforced, partitioned Parquet files (Silver) and rollup daily analytics (Gold).

### Components
- **DuckDB Container / Script**: Executes S3-direct SQL transformations.
- **Scheduler**: n8n Cron Trigger or cron daemon running every 5–15 minutes.

### Step-by-Step Transformations
#### Step 1: Raw $\rightarrow$ Curated (Bronze to Silver)
DuckDB SQL script (`etl_curated.sql`):
```sql
INSTALL httpfs; LOAD httpfs;
SET s3_endpoint='host.docker.internal:9000';
SET s3_access_key_id='cdeadmin';
SET s3_secret_access_key='cdepassword123';
SET s3_use_ssl=false;
SET s3_url_style='path';

COPY (
  SELECT 
    event_id::VARCHAR AS event_id,
    strptime(timestamp, '%Y-%m-%dT%H:%M:%SZ') AS event_timestamp,
    severity::VARCHAR AS severity,
    reading::DOUBLE AS reading,
    source::VARCHAR AS source,
    current_timestamp AS ingested_at
  FROM read_json_auto('s3://lake-raw/**/*.json')
  WHERE event_id IS NOT NULL
) TO 's3://lake-curated/telemetry/' (FORMAT PARQUET, PARTITION_BY (severity), OVERWRITE_OR_IGNORE 1);
```

#### Step 2: Curated $\rightarrow$ Publish (Silver to Gold)
DuckDB SQL script (`etl_publish.sql`):
```sql
COPY (
  SELECT 
    date_trunc('day', event_timestamp) AS date,
    source,
    severity,
    count(*) AS total_events,
    avg(reading) AS avg_reading,
    max(reading) AS max_reading
  FROM read_parquet('s3://lake-curated/telemetry/**/*.parquet')
  GROUP BY 1, 2, 3
) TO 's3://lake-publish/daily_summary/' (FORMAT PARQUET, OVERWRITE_OR_IGNORE 1);
```

### Verification & Testing
Execute test queries directly against MinIO via DuckDB CLI:
```bash
duckdb -c "INSTALL httpfs; LOAD httpfs; SELECT * FROM read_parquet('s3://lake-publish/daily_summary/**/*.parquet') LIMIT 5;"
```

---

## Phase 6: Published Data Egress & Serving API

### Objective
Provide low-latency ($<20\text{ ms}$) query endpoints for Virtual Assistants, Dashboards, and external consumers, secured behind Kong.

### Components
- **PostgreSQL Operational DB**: Holds mirrored Gold aggregates.
- **Serving Microservice (PostgREST / FastAPI)**: Translates REST calls into SQL queries.
- **Kong Egress Route**: Enforces API keys and caches responses (`proxy-cache`).

### Setup Instructions
1. Create a lightweight FastAPI serving container (`serving-api`):
   ```python
   from fastapi import FastAPI
   import duckdb

   app = FastAPI(title="CDE Published Data API")

   @app.get("/api/v1/metrics/daily")
   def get_daily_metrics():
       con = duckdb.connect()
       con.execute("INSTALL httpfs; LOAD httpfs; ...")
       df = con.execute("SELECT * FROM read_parquet('s3://lake-publish/daily_summary/**/*.parquet')").df()
       return df.to_dict(orient="records")
   ```
2. Register the service in Kong Gateway:
   ```bash
   # Service definition
   curl.exe -i -X POST http://localhost:8001/services \
     -d "name=cde-publish-service" \
     -d "url=http://host.docker.internal:8000"

   # Route definition
   curl.exe -i -X POST http://localhost:8001/services/cde-publish-service/routes \
     -d "name=publish-route" \
     -d "paths[]=/api/v1/metrics"

   # Enable Proxy Caching (10-minute TTL)
   curl.exe -i -X POST http://localhost:8001/routes/publish-route/plugins \
     -d "name=proxy-cache" \
     -d "config.response_code[]=200" \
     -d "config.content_type[]=application/json" \
     -d "config.cache_ttl=600"
   ```

### Verification & Testing
1. Call the endpoint through Kong:
   ```bash
   curl.exe -i http://localhost:8088/api/v1/metrics/daily
   ```
2. Check headers: The first request returns `X-Cache-Status: Miss`; subsequent requests return `X-Cache-Status: Hit` in $< 2\text{ ms}$.

---

## Phase 7: End-to-End Integration, Observability & Hardening

### Objective
Validate end-to-end telemetry flow from source ingestion through to published consumption, configure monitoring, and enforce security policies.

### Deliverables & Checklist
- [ ] **End-to-End Ingestion Validation:** Pushing a mock sensor batch triggers both the urgent alert (Redis) and persists to MinIO raw.
- [ ] **Automated Lakehouse ETL:** Scheduled DuckDB job runs without manual intervention and updates Gold Parquet.
- [ ] **Egress Performance:** Virtual Assistant queries `/api/v1/metrics` and receives responses in $< 20\text{ ms}$.
- [ ] **Security Hardening:**
  - `key-auth` enabled on public routes.
  - Rate limiting enforced (e.g. 100 requests/minute per consumer).
  - CORS headers restricted to permitted dashboard origins.
- [ ] **Monitoring & Health Dashboard:**
  - Kong Manager active on `:8002`.
  - Container health checks monitored across all services.

---

## Implementation Progress Tracker

| Phase | Description | Status | Target Date | Notes |
| :--- | :--- | :--- | :--- | :--- |
| **Phase 1** | Kong Gateway OSS 3.9 Setup | **Completed** | Day 1 | Running on `:8088`, `:8001`, `:8002` |
| **Phase 2** | n8n Orchestrator Deployment | **Completed** | Day 1 | Running on `:5678`, connected to `cde-network` |
| **Phase 3** | Fast-Path Alert Lane (Redis Streams) | **Ready to Build** | Day 2 | Redis available on `:6379` |
| **Phase 4** | MinIO Object Store (Bronze Zone) | **Pending** | Day 3 | Buckets: `raw`, `curated`, `publish` |
| **Phase 5** | DuckDB/Polars Lakehouse ETL | **Pending** | Day 4 | SQL transformation scripts |
| **Phase 6** | Egress API & Kong Caching | **Pending** | Day 5 | PostgREST / FastAPI serving |
| **Phase 7** | Hardening & E2E Validation | **Pending** | Day 6 | Final acceptance & monitoring |
