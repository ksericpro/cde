# CDE Security Incident Data Mart (`Raw` -> `Curated` -> `Published`)

This directory contains the storage, Medallion ETL Data Plane, and Serving API stack for the CDE Security Incident Data Mart, as specified in **[docs/data_model.md](file:///c:/Projects/cde/docs/data_model.md)** and **[docs/development_plan.md](file:///c:/Projects/cde/docs/development_plan.md)**.

---

## 1. Implementation Progress Tracker

| Phase | Scope | Status |
| :--- | :--- | :--- |
| **Phase 1** | **Storage & Medallion Schema Initialization** (`cde-datamart-db` on `:5433`, `cde-minio` on `:9000/:9001`, 12 tables across `raw`, `silver`, `mart_security`, S3 buckets `lake-raw`, `lake-curated`, `lake-publish`) | **Completed & Verified** |
| **Phase 2** | **Hybrid n8n Scheduled Poller + Medallion ETL & Serving API** (`n8n` workflow `CdeImopsDataMart1` triggering `cde-datamart-etl` on `:8090` every 5 mins) | **Completed & Verified** |
| **Phase 3** | **Data Catalogue, Self-Service API Key Portal (`/catalog`) & Kong API Gateway (`:8088`) Egress** (`key-auth` protection + Gold-only publishing) | **Completed & Verified** |
| **Phase 4** | **Connect Grafana (`:3000`) to `cde-datamart-db` & Provision Security Data Mart Dashboard** (`http://localhost:3000/d/cde-security-datamart`) | **Completed & Verified** |

---

## 2. Hybrid Architecture & Service URLs

| Layer | Service / Container | URL / Endpoint | Credentials / Notes |
| :--- | :--- | :--- | :--- |
| **n8n Orchestrator (Control Plane)** | `n8n-server` / `n8n-proxy` | **[https://localhost:5678](https://localhost:5678)** | Active workflow: **`iMOPS Security Incident Poller & Medallion Data Mart ETL`** (`ID: CdeImopsDataMart1`) |
| **n8n Poller Workflow Canvas** | `n8n-server` | **[https://localhost:5678/workflow/CdeImopsDataMart1](https://localhost:5678/workflow/CdeImopsDataMart1)** | Visual 5-minute schedule trigger & 5-step Medallion pipeline |
| **n8n Poller Execution History** | `n8n-server` | **[https://localhost:5678/workflow/CdeImopsDataMart1/executions](https://localhost:5678/workflow/CdeImopsDataMart1/executions)** | View every 5-minute scheduled run and node JSON outputs |
| **Data Mart ETL & Serving API (Data Plane)** | `cde-datamart-etl` | **[http://localhost:8090/api/v1/datamart/security/summary](http://localhost:8090/api/v1/datamart/security/summary)** | Serves Bronze/Silver/Gold counts, health status, and JSON/CSV Data Mart exports |
| **MinIO S3 Web Console** | `cde-minio` | **[http://localhost:9001](http://localhost:9001)** | User: `cdeadmin` / Pass: `cdepassword123` (Buckets: `lake-raw`, `lake-curated`, `lake-publish`) |
| **MinIO S3 API** | `cde-minio` | `http://localhost:9000` | Internal Docker alias: `http://cde-minio:9000` |
| **PostgreSQL 16 Data Mart** | `cde-datamart-db` | `localhost:5433` (Internal: `cde-datamart-db:5432`) | DB: `cde_datamart` / User: `cdeadmin` / Pass: `cdepassword123` |
| **iMOPS Source Backend** | `imops-backend` | `http://localhost:13000` | Basic Auth: `dors_user@isems.com` / `1Pu1znaPbTqXcyC5KVpP` |
| **Kong API Gateway Proxy** | `kong-gateway` | `http://localhost:8088` | Admin API: `http://localhost:8001` / Kong Manager UI: **[http://localhost:8002](http://localhost:8002)** |
| **Grafana Dashboards** | `cde-grafana` | **[http://localhost:3000](http://localhost:3000)** | User: `admin` / Pass: `admin123` |
| **Kibana (ELK Logs)** | `cde-kibana` | **[http://localhost:5601](http://localhost:5601)** | Dashboard: **[CDE Platform Overview](http://localhost:5601/app/dashboards#/view/cde-platform-overview)** |

---

## 3. Startup, Resume & Verification Commands

### A. Start / Resume All CDE Stacks
Run these commands in PowerShell from `c:\Projects\cde`:

```powershell
# 1. Start Data Mart Stack (Postgres :5433, MinIO :9000/:9001, ETL API :8090)
docker compose -f c:\Projects\cde\datamart\docker-compose.yml up -d

# 2. Start n8n Orchestrator (:5678)
docker compose -f c:\Projects\cde\n8n\docker-compose.yml up -d

# 3. Start Kong API Gateway (:8088 / Admin :8001 / Manager :8002) — Required for Phase 3
docker compose -f c:\Projects\cde\apigw\docker-compose.yml up -d

# 4. Start Prometheus & Grafana (:3000) — Required for Phase 4
docker compose -f c:\Projects\cde\grafana\docker-compose.yml up -d

# 5. (Optional) Start ELK Log Stack (Kibana :5601)
docker compose -f c:\Projects\cde\elk\docker-compose.yml up -d
```

### B. Verify Data Mart Stack (Containers, 11 Tables, 3 Buckets & Row Counts)
```powershell
powershell -ExecutionPolicy Bypass -File c:\Projects\cde\datamart\scripts\verify_datamart.ps1
```

### C. Check Scheduled Poller Results & Trigger On-Demand Run
```powershell
# 1. Check ETL Health, Watermarks & Last Run Result
Invoke-RestMethod -Uri "http://localhost:8090/api/v1/datamart/security/health" | ConvertTo-Json -Depth 5

# 2. Trigger an Immediate Poll via n8n Webhook
curl.exe -k -X POST "https://localhost:5678/webhook/datamart-sync"

# 3. Stream Live ETL Container Logs
docker logs -f cde-datamart-etl

# 4. Inspect Raw Batch Audit Trail in PostgreSQL
docker exec cde-datamart-db psql -U cdeadmin -d cde_datamart -c "SELECT pulled_at, endpoint, site_name, record_count, s3_object_key FROM raw.imops_api_payloads ORDER BY pulled_at DESC LIMIT 16;"
```

---

## 4. Data Mart Serving API Endpoints (`http://localhost:8090`)

All data endpoints support `?format=json` (default), `?format=csv` (downloadable CSV), `?site=<name>`, and `?limit=<n>`:

| Endpoint | URL | Description |
| :--- | :--- | :--- |
| **Summary & Zone Counts** | [http://localhost:8090/api/v1/datamart/security/summary](http://localhost:8090/api/v1/datamart/security/summary) | Row counts across `raw`, `silver`, and `mart_security` |
| **Health & Watermarks** | [http://localhost:8090/api/v1/datamart/security/health](http://localhost:8090/api/v1/datamart/security/health) | Shows `hybrid_n8n_orchestrated` status and `lastSyncResult` |
| **Gold Mart 1 — Daily Site KPIs (JSON)** | [http://localhost:8090/api/v1/datamart/security/daily-kpis](http://localhost:8090/api/v1/datamart/security/daily-kpis) | Daily incidents, active/ack/resolved counts, MTTA, MTTR, SLA breaches |
| **Gold Mart 1 — Daily Site KPIs (CSV)** | [http://localhost:8090/api/v1/datamart/security/daily-kpis?format=csv](http://localhost:8090/api/v1/datamart/security/daily-kpis?format=csv) | Direct CSV download |
| **Gold Mart 2 — Incident Hotspots (JSON)** | [http://localhost:8090/api/v1/datamart/security/hotspots](http://localhost:8090/api/v1/datamart/security/hotspots) | Top recurring site/zone/device alarm hotspots |
| **Gold Mart 2 — Incident Hotspots (CSV)** | [http://localhost:8090/api/v1/datamart/security/hotspots?format=csv](http://localhost:8090/api/v1/datamart/security/hotspots?format=csv) | Direct CSV download |
| **Gold Mart 3 — SLA Compliance (JSON)** | [http://localhost:8090/api/v1/datamart/security/sla-compliance](http://localhost:8090/api/v1/datamart/security/sla-compliance) | Operator & site SLA compliance % and response speed |
| **Gold Mart 3 — SLA Compliance (CSV)** | [http://localhost:8090/api/v1/datamart/security/sla-compliance?format=csv](http://localhost:8090/api/v1/datamart/security/sla-compliance?format=csv) | Direct CSV download |
| **Gold Mart 4 — Device Reliability (JSON)** | [http://localhost:8090/api/v1/datamart/security/device-reliability](http://localhost:8090/api/v1/datamart/security/device-reliability) | Device offline counts, total incidents triggered, and health status |
| **Gold Mart 4 — Device Reliability (CSV)** | [http://localhost:8090/api/v1/datamart/security/device-reliability?format=csv](http://localhost:8090/api/v1/datamart/security/device-reliability?format=csv) | Direct CSV download |
| **Silver Fact — Curated Incidents (JSON)** | [http://localhost:8090/api/v1/datamart/security/incidents](http://localhost:8090/api/v1/datamart/security/incidents) | Full deduplicated incident list (`?status=active&severity=critical`) |
| **Silver Fact — Curated Incidents (CSV)** | [http://localhost:8090/api/v1/datamart/security/incidents?format=csv](http://localhost:8090/api/v1/datamart/security/incidents?format=csv) | Direct CSV download |
