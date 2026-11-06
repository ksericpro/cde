# CDE Security Incident Data Mart (`Raw` -> `Curated` -> `Published`)

This directory contains the storage, Medallion ETL Data Plane, and Serving API stack for the CDE Security Incident Data Mart, as specified in **[docs/data_model.md](file:///c:/Projects/cde/docs/data_model.md)** and **[docs/development_plan.md](file:///c:/Projects/cde/docs/development_plan.md)**.

---

## 1. Hybrid Architecture (Control Plane + Data Plane)

| Layer | Service / Container | Host Port | Role |
| :--- | :--- | :--- | :--- |
| **Control Plane (Orchestration)** | **n8n** (`n8n-server` / `n8n-proxy`) | `5678` (HTTPS) | Runs the active 5-minute workflow **`iMOPS Security Incident Poller & Medallion Data Mart ETL`** (`ID: CdeImopsDataMart1`), polls iMOPS health, triggers `/api/v1/datamart/security/sync`, and logs every execution in the n8n UI ([https://localhost:5678/workflow/CdeImopsDataMart1/executions](https://localhost:5678/workflow/CdeImopsDataMart1/executions)) |
| **Data Plane (ETL & Serving API)** | **`cde-datamart-etl`** | `8090` | Executes heavy Medallion ETL (`Raw` `.json.gz` -> `Curated` Star Schema -> `Published` Gold Marts) and serves JSON/CSV REST APIs |
| **Relational Data Mart** | **PostgreSQL 16** (`cde-datamart-db`) | `5433` | Stores `raw`, `silver` (Star Schema), and `mart_security` (Gold Data Marts) |
| **Lakehouse Object Storage** | **MinIO S3** (`cde-minio`) | `9000` / `9001` | Stores `s3://lake-raw`, `s3://lake-curated`, and `s3://lake-publish` ([http://localhost:9001](http://localhost:9001)) |

---

## 2. Quick Start (Phases 1 & 2)

### Deploy Storage + Medallion ETL Stack
```powershell
powershell -ExecutionPolicy Bypass -File datamart/scripts/deploy_datamart.ps1
```

### Verify Schemas, Tables, Buckets & Medallion Row Counts
```powershell
powershell -ExecutionPolicy Bypass -File datamart/scripts/verify_datamart.ps1
```

---

## 3. Data Mart Serving API Endpoints (`http://localhost:8090`)

All endpoints support `?format=json` (default), `?format=csv` (downloadable CSV), `?site=<name>`, and `?limit=<n>`:

- **Summary & Zone Counts**: `GET http://localhost:8090/api/v1/datamart/security/summary`
- **Health & ETL Watermarks**: `GET http://localhost:8090/api/v1/datamart/security/health`
- **Trigger Immediate ETL Poll (via n8n Webhook)**: `POST https://localhost:5678/webhook/datamart-sync`
- **Trigger Immediate ETL Poll (Direct Data Plane)**: `POST http://localhost:8090/api/v1/datamart/security/sync`
- **Gold Mart 1 — Daily Site KPIs**: `GET http://localhost:8090/api/v1/datamart/security/daily-kpis?format=json|csv`
- **Gold Mart 2 — Incident Hotspots**: `GET http://localhost:8090/api/v1/datamart/security/hotspots?format=json|csv`
- **Gold Mart 3 — SLA Compliance**: `GET http://localhost:8090/api/v1/datamart/security/sla-compliance?format=json|csv`
- **Gold Mart 4 — Device Reliability**: `GET http://localhost:8090/api/v1/datamart/security/device-reliability?format=json|csv`
- **Silver Fact — Curated Incidents**: `GET http://localhost:8090/api/v1/datamart/security/incidents?format=json|csv`
