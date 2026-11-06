# CDE Security Incident Data Mart — Architecture, Data Model & Gap Analysis

> **Objective:** Extract security-related incident data from **iMOPS** at regular intervals, persist it through a **Medallion Lakehouse + Relational Data Mart (`Raw` $\rightarrow$ `Curated` $\rightarrow$ `Published`)**, and expose curated analytical Data Marts for BI reporting, SLA auditing, Digital Twins, and AI Assistants.

---

## 1. End-to-End Architecture (`Raw` $\rightarrow$ `Curated` $\rightarrow$ `Published`)

To get the best of both worlds—**immutable file archival (Parquet/JSONL)** and **fast SQL query performance for BI/Dashboards (PostgreSQL)**—we combine **MinIO Object Storage** (Files) with **PostgreSQL + DuckDB** (Database):

![CDE Security Incident Data Mart Architecture](cde-data-model.png)

```
 ┌─────────────────────────────────────────────────────────────────────────────────────────┐
 │                           SOURCE: iMOPS BACKEND (:13000)                                │
 │  • GET /api/visualization/incidents      (Active, Acknowledged, Resolved Incidents)     │
 │  • GET /api/visualization/hierarchy      (Sites, Buildings, Floors, Zones)              │
 │  • GET /api/visualization/device-health  (Cameras, Sensors, BWC Online/Offline)         │
 │  • GET /api/visualization/sla & summons  (SLA Thresholds, Breaches, Security Summons)   │
 └───────────────────────────────────────────┬─────────────────────────────────────────────┘
                                             │
                                             ▼  Regular Interval Poll (Every 5–15 mins)
 ┌─────────────────────────────────────────────────────────────────────────────────────────┐
 │                     ORCHESTRATOR & STATE STORE: n8n (:5678) + Redis                     │
 │  • Loops over assigned sites & pages (page=1..N, limit=100)                             │
 │  • Tracks high-water mark cursor (last_poll_timestamp) in Redis / Postgres              │
 └───────────────────────────────────────────┬─────────────────────────────────────────────┘
                                             │
                                             ▼
 ═══════════════════════════════════════════════════════════════════════════════════════════
   ZONE 1: RAW / BRONZE (Immutable Landing Zone — Files + Staging Table)
 ═══════════════════════════════════════════════════════════════════════════════════════════
   🪣 MinIO: s3://lake-raw/imops/incidents/dt=YYYY-MM-DD/batch_<ts>.json.gz
   🗄️ Postgres: raw.imops_api_payloads (append-only JSONB audit log with batch_id, pulled_at)
                                             │
                                             ▼  ETL Step 1: DuckDB / Polars (Every 15 mins)
                                             │  • Unnests JSON arrays, casts types & UTC timestamps
                                             │  • Deduplicates & tracks status transitions (SCD Type 1 & 2)
 ═══════════════════════════════════════════════════════════════════════════════════════════
   ZONE 2: CURATED / SILVER (Cleaned, Deduplicated Star Schema — Parquet + Relational)
 ═══════════════════════════════════════════════════════════════════════════════════════════
   🪣 MinIO: s3://lake-curated/security/fact_incidents/*.parquet (Partitioned by year/month)
   🗄️ Postgres (silver.*):
      • silver.fact_incidents_current        (1 row per incidentNumber — latest state)
      • silver.fact_incident_state_history   (SCD Type 2 audit of Active -> Ack -> Resolved)
      • silver.dim_location                  (Site -> Building -> Floor -> Zone hierarchy)
      • silver.dim_device                    (Camera / Sensor / Proscalar Point inventory)
                                             │
                                             ▼  ETL Step 2: SQL / DuckDB Rollups
                                             │  • Calculates MTTA, MTTR, SLA Breach %, Hotspots
 ═══════════════════════════════════════════════════════════════════════════════════════════
   ZONE 3: PUBLISHED / GOLD (Business Data Marts — Ready for BI, Dashboards & AI)
 ═══════════════════════════════════════════════════════════════════════════════════════════
   🪣 MinIO: s3://lake-publish/mart_security/*.parquet
   🗄️ Postgres (mart_security.*):
      • mart_security.dm_daily_site_kpis     (Daily incidents, MTTA, MTTR, SLA % by Site/Zone)
      • mart_security.dm_incident_hotspots   (Top recurring incident types & cameras)
      • mart_security.dm_sla_compliance      (Breached vs. Within-SLA incidents & operators)
      • mart_security.dm_device_reliability  (Camera offline frequency vs. incident volume)
                                             │
                                             ▼
 ┌─────────────────────────────────────────────────────────────────────────────────────────┐
 │              CONSUMPTION LAYER (Behind Kong API Gateway :8088 + Direct SQL)             │
 │  • Grafana / Superset / PowerBI / Excel (Direct PostgreSQL connection to mart_security) │
 │  • FastAPI / PostgREST -> Kong (:8088/api/v1/datamart/security/*)                       │
 │  • Omnichannel AI Assistant & Predictive Engine                                         │
 └─────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Recommended Technology Stack (Matching Your Existing Local Environment)

All required images are **already downloaded in your local Docker image cache** (`docker images`), meaning zero external dependency bloat:

| Layer | Technology | Why This Choice for CDE | Local Image Available? |
| :--- | :--- | :--- | :---: |
| **Regular Interval Poller** | **n8n** (`n8n-server:5678`) | Already running; Schedule Trigger + HTTP Request node handles Basic Auth, pagination, and retries. | ✅ Running (`docker.n8n.io/n8nio/n8n:latest`) |
| **Raw File Lake (Bronze/Silver/Gold)** | **MinIO** (`cde-minio:9000`) | S3-compatible object storage for immutable `.json.gz` raw dumps and partitioned `.parquet` files. | ✅ Cached (`cgr.dev/chainguard/minio:latest`) |
| **Relational Data Mart DB** | **PostgreSQL 16** (`cde-datamart-db:5433`) | Best for structured Star Schema (`raw`, `silver`, `mart_security` schemas), indexing, `JSONB`, and direct connections from Grafana, Excel, or PowerBI. | ✅ Cached (`postgres:16-alpine`) |
| **ETL & Transformation Engine** | **Python (Polars / DuckDB)** or **Postgres SQL Procedures** | DuckDB & Polars read/write both MinIO Parquet and PostgreSQL tables in milliseconds; Postgres native SQL (`INSERT ... ON CONFLICT DO UPDATE`) handles upserts cleanly. | ✅ Cached |
| **Egress API & Caching** | **FastAPI / PostgREST + Kong (`:8088`)** | Exposes Gold Data Mart views as REST/CSV endpoints with Kong `key-auth` and `proxy-cache`. | ✅ Running (`kong:3.9`) |

---

## 3. Data Model Design Across the 3 Zones

### 3.1 Raw Zone (`raw` schema & `s3://lake-raw/`)
Stores the exact unmodified JSON response from iMOPS at each polling interval for full replayability and audit compliance.

* **File Path:** `s3://lake-raw/imops/incidents/dt=YYYY-MM-DD/batch_<ts>.json.gz`
* **Database Table (`raw.imops_api_payloads`):**
  | Column | Type | Description |
  | :--- | :--- | :--- |
  | `batch_id` | `UUID PK` | Unique ID for the polling run |
  | `endpoint` | `VARCHAR(120)` | e.g., `/api/visualization/incidents` |
  | `site_name` | `VARCHAR(100)` | Polled site (e.g., `SOV @ 38ALT`, `Taylor's University`, `ISEMS Pte Ltd`) |
  | `pulled_at` | `TIMESTAMPTZ` | Exact UTC timestamp when n8n fetched the batch |
  | `record_count` | `INTEGER` | Number of incident items in `data.items[]` |
  | `raw_payload` | `JSONB` | Complete unmutated JSON response from iMOPS |

---

### 3.2 Curated Zone (`silver` schema & `s3://lake-curated/`) — Star Schema Core
Cleans, normalizes, and deduplicates the raw batches into conformed **Dimension** and **Fact** tables.

#### Dimension 1: `silver.dim_location` (Synced from `/api/visualization/hierarchy`)
* `location_key` (PK, Surrogate Hash of `site + building + floor + zone`)
* `site_id`, `site_name`, `building_id`, `building_name`, `floor_id`, `floor_name`, `zone_id`, `zone_name`

#### Dimension 2: `silver.dim_device` (Synced from `/api/visualization/equipment` & `/device-health`)
* `device_key` (PK), `device_id`, `device_name` (e.g. `bin_centre`, `OT-MAIN GATE`), `device_type` (`CCTV`, `Access Reader`, `BWC`), `location_key`, `current_health_status`

#### Dimension 3: `silver.dim_incident_type`
* `incident_type_key` (PK), `incident_type_code` (e.g. `crowding`, `loitering`, `door_forced_open`, `fire_alarm`), `category` (`Video Analytics`, `Access Control`, `Safety/Fire`, `Device Health`), `default_severity`, `sla_target_minutes`

#### Fact Table 1: `silver.fact_incidents_current` (Upserted by `incident_number`)
Represents the **latest known truth** for every security incident:
| Column | Type | Description |
| :--- | :--- | :--- |
| `incident_number` | `VARCHAR(40) PK` | Natural key from iMOPS (e.g., `INC-2611-00042`) |
| `event_id` | `VARCHAR(64)` | Upstream MongoDB `_id` (`6ae97a213469fe8b8d21b9e9`) |
| `location_key` | `VARCHAR(64) FK` | Links to `silver.dim_location` |
| `device_key` | `VARCHAR(64) FK` | Links to `silver.dim_device` |
| `incident_type` | `VARCHAR(64)` | Normalized type (`Loitering`, `Door Forced Open`, `Device Offline`) |
| `title` | `TEXT` | Incident title / description |
| `severity` | `VARCHAR(20)` | Standardized: `low`, `medium`, `high`, `critical` |
| `status` | `VARCHAR(20)` | Current state: `active`, `attend_now`, `acknowledged`, `resolved` |
| `operator_name` | `VARCHAR(100)` | Operator who acknowledged/resolved |
| `detected_at` | `TIMESTAMPTZ` | When the incident occurred (`detectedAt`) |
| `acknowledged_at` | `TIMESTAMPTZ` | First transition to `acknowledged` |
| `resolved_at` | `TIMESTAMPTZ` | Transition to `resolved` |
| `mtta_seconds` | `INTEGER` | `EXTRACT(EPOCH FROM (acknowledged_at - detected_at))` |
| `mttr_seconds` | `INTEGER` | `EXTRACT(EPOCH FROM (resolved_at - detected_at))` |
| `is_sla_breached` | `BOOLEAN` | True if response/resolution exceeded SLA threshold |
| `source_system` | `VARCHAR(40)` | `imops_va`, `proscalar_n8n`, `sicc_va`, `dors_va` |
| `first_ingested_at` | `TIMESTAMPTZ` | First time seen by CDE poller |
| `last_updated_at` | `TIMESTAMPTZ` | Last time updated by CDE poller |

#### Fact Table 2: `silver.fact_incident_state_history` (SCD Type 2 Audit Log)
* Captures a new row **only when an incident's `status` or `severity` changes** between polling intervals (`old_status` $\rightarrow$ `new_status`, `changed_at`, `operator`).

---

### 3.3 Published Zone (`mart_security` schema & `s3://lake-publish/`) — Business Data Marts
Pre-joined, aggregated tables and views tailored for specific business consumers:

1. **`mart_security.dm_daily_site_kpis` (Executive & Operations Mart)**
   * **Grain:** `incident_date + site_name + floor_name + zone_name + incident_type + severity`
   * **Metrics:** `total_incidents`, `active_count`, `acknowledged_count`, `resolved_count`, `resolution_rate_pct`, `avg_mtta_minutes`, `avg_mttr_minutes`, `p95_mttr_minutes`, `sla_breach_count`.
2. **`mart_security.dm_incident_hotspots` (Spatial & Camera Hotspot Mart)**
   * **Grain:** `site_name + zone_name + device_name + incident_type` (Rolling 7d / 30d)
   * **Metrics:** `incident_count_7d`, `incident_count_30d`, `prev_7d_trend_pct`, `critical_alarm_count`, `false_alarm_rate`.
3. **`mart_security.dm_sla_compliance` (Compliance & Guard Response Mart)**
   * **Grain:** `incident_date + site_name + operator_name + severity`
   * **Metrics:** `incidents_handled`, `within_sla_count`, `breached_sla_count`, `sla_compliance_pct`, `fastest_ack_sec`, `slowest_ack_sec`.
4. **`mart_security.dm_device_reliability` (Camera & Sensor Health vs. Incident Volume Mart)**
   * **Grain:** `incident_date + site_name + device_name + device_type`
   * **Metrics:** `offline_events_count`, `total_downtime_minutes`, `uptime_pct`, `incidents_triggered_count`.

---

## 4. Gap Analysis: What Exists Today vs. What Needs to Be Built

Reviewing your current `c:\Projects\cde` repository against this Data Mart architecture reveals **6 concrete gaps**:

| # | Gap Area | Current State in `c:\Projects\cde` | Impact / Risk | Recommended Fix |
| :- | :--- | :--- | :--- | :--- |
| **1** | **No Data Mart Storage Containers Deployed** | `MinIO` and `PostgreSQL` are described in `readme.md` and `development_plan.md`, but only `kong-db` (for Kong internal state) is running. There is no `datamart/` stack yet. | Nowhere to persist `raw` $\rightarrow$ `curated` $\rightarrow$ `published` files or tables. | Create `datamart/docker-compose.yml` running **`cde-datamart-db`** (`postgres:16-alpine` on `:5433`) and **`cde-minio`** (`:9000`/`:9001`). |
| **2** | **Push-Only vs. Scheduled Pull in `n8n`** | `n8n` currently only has `proscalar_ingestion_workflow.json` (which waits for inbound webhooks). There is no scheduled poller fetching from iMOPS `:13000`. | Incidents created directly in iMOPS (like VA camera alerts, BWC, or Device Offline) never enter CDE storage. | Build an **n8n Scheduled Poller Workflow** (runs every 5–15 mins) that pulls `/api/visualization/incidents`, `/hierarchy`, and `/sla`. |
| **3** | **iMOPS Pagination & Delta Watermarking** | `/api/visualization/incidents` uses `daysBack`, `page`, and `limit` (not a strict `updated_since` cursor). | Polling without pagination misses records past page 1; polling without deduplication duplicates active incidents every 5 minutes. | Have the poller iterate pages (`daysBack=7&page=1..N&limit=100`), dump raw JSON to Bronze, and use `ON CONFLICT (incident_number) DO UPDATE` in Silver. |
| **4** | **Stateful Incident Lifecycle (MTTA / MTTR)** | Existing Phase 5 SQL in `development_plan.md` treats events as immutable sensor readings (`OVERWRITE_OR_IGNORE`). | Security incidents mutate over time (`active` $\rightarrow$ `acknowledged` $\rightarrow$ `resolved`). Append-only logic cannot compute resolution time or SLA breaches. | Track `first_seen_at`, `acknowledged_at`, and `resolved_at` in `silver.fact_incidents_current` and log transitions in `silver.fact_incident_state_history`. |
| **5** | **Multi-Source Schema Fragmentation** | Incident payloads differ across **Proscalar** (`eventCode: "5002"`), **SICC/DORS VA** (`/va/sov-38alt-...`), and **iMOPS Native** (`INC-2611-00042`). | Reporting queries break if severity (`CRITICAL` vs `critical`) or incident types aren't standardized. | Enforce a canonical mapping table in the Silver ETL step so all sources share unified `severity`, `status`, and `incident_type` taxonomies. |
| **6** | **Visualization & Export Integration** | Grafana currently only queries Prometheus time-series metrics (`:9090`), not business Data Mart tables. | Stakeholders cannot export incident summary tables or SLA reports from Grafana. | Add `cde-datamart-db` as a **PostgreSQL Datasource** in Grafana (`grafana/provisioning/datasources/`) so Grafana can query and export `mart_security.*` directly to CSV! |

---

## 5. Phased Implementation Plan

### Step 1: Deploy the Data Mart Storage Stack (`datamart/`)
1. Create `c:\Projects\cde\datamart\docker-compose.yml` with:
   - **`cde-datamart-db`** (`postgres:16-alpine`, port `5433`) initialized with `init_datamart.sql` creating schemas: `raw`, `silver`, and `mart_security`.
   - **`cde-minio`** (`cgr.dev/chainguard/minio:latest`, ports `9000`/`9001`) with buckets: `lake-raw`, `lake-curated`, `lake-publish`.

### Step 2: Build the Scheduled iMOPS Poller & ETL Pipeline
1. **Option A (n8n Scheduled Workflow):**
   - `Schedule Trigger (Every 5m)` $\rightarrow$ `HTTP GET http://imops-backend:3000/api/visualization/incidents?daysBack=7&limit=100` $\rightarrow$ Write Raw JSON to `MinIO (lake-raw)` & `raw.imops_incident_batches` $\rightarrow$ Trigger Silver/Gold SQL transformation.
2. **Option B (Dedicated Python/Node ETL Worker Container in `datamart/`):**
   - Lightweight daemon container that polls `/api/visualization/incidents`, `/hierarchy`, `/device-health`, and `/sla` on a configurable cron interval, archives `.json.gz` + `.parquet` to MinIO, and runs the `raw` $\rightarrow$ `silver` $\rightarrow$ `mart_security` upserts and rollups in PostgreSQL.

### Step 3: Connect Grafana & Kong Egress to the Published Data Mart
1. Auto-provision `cde-datamart-db` (`PostgreSQL`) in `grafana/provisioning/datasources/datasources.yaml`.
2. Add a **Security Incident Data Mart Dashboard** in Grafana showing Daily Incidents by Site/Zone, MTTA/MTTR, SLA Compliance %, and a full exportable Incident Table.
3. Expose `/api/v1/datamart/security/*` via Kong Gateway (`:8088`) for external consumers and AI Assistants.
