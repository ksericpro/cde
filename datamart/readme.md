# CDE Security Incident Data Mart (`Raw` -> `Curated` -> `Published`)

This directory contains the storage, Medallion ETL Poller, and Serving API stack for the CDE Security Incident Data Mart, as specified in **[docs/data_model.md](file:///c:/Projects/cde/docs/data_model.md)** and **[docs/development_plan.md](file:///c:/Projects/cde/docs/development_plan.md)**.

---

## 1. Stack Components

| Service | Container Name | Host Port | Purpose |
| :--- | :--- | :--- | :--- |
| **PostgreSQL 16** | `cde-datamart-db` | `5433` | Relational Data Mart (`raw`, `silver`, and `mart_security` schemas) |
| **MinIO S3 API** | `cde-minio` | `9000` | S3-compatible object storage (`s3://lake-raw`, `s3://lake-curated`, `s3://lake-publish`) |
| **MinIO Console** | `cde-minio` | `9001` | Web UI at [http://localhost:9001](http://localhost:9001) (`cdeadmin` / `cdepassword123`) |
| **Medallion ETL & Serving API** | `cde-datamart-etl` | `8090` | Polls iMOPS every 5 mins (`Raw` -> `Curated` -> `Published`) & serves JSON/CSV Data Mart APIs |

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
- **Trigger Immediate ETL Poll**: `POST http://localhost:8090/api/v1/datamart/security/sync`
- **Gold Mart 1 — Daily Site KPIs**: `GET http://localhost:8090/api/v1/datamart/security/daily-kpis?format=json|csv`
- **Gold Mart 2 — Incident Hotspots**: `GET http://localhost:8090/api/v1/datamart/security/hotspots?format=json|csv`
- **Gold Mart 3 — SLA Compliance**: `GET http://localhost:8090/api/v1/datamart/security/sla-compliance?format=json|csv`
- **Gold Mart 4 — Device Reliability**: `GET http://localhost:8090/api/v1/datamart/security/device-reliability?format=json|csv`
- **Silver Fact — Curated Incidents**: `GET http://localhost:8090/api/v1/datamart/security/incidents?format=json|csv`
