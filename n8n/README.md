# n8n Workflow Ingestion Engine (CDE)

This module deploys **n8n** as the primary Orchestration & Ingestion Engine for the Common Data Environment (CDE), referenced from the enterprise setup in `C:\projects\ZAARR-DTE\taylor-imops-lite`.

---

## Port Allocations & Access

| Service | Port | Description | URL |
| :--- | :--- | :--- | :--- |
| **n8n Web UI / API** | **`5678`** | Visual Workflow Designer & Webhook receiver | **[http://localhost:5678](http://localhost:5678)** |
| **Via Kong Gateway** | **`8088`** | Public ingress reverse-proxied through Kong | `http://localhost:8088/n8n/` |

---

## Quick Start

### 1. Launch the n8n Container
Run the following from the `n8n` directory:

```bash
docker compose up -d
```

### 2. Verify Container Health
```bash
docker compose ps
```
The container `cde-n8n` should report status `Up`.

Check the health endpoint:
```bash
curl.exe http://localhost:5678/healthz
```
Expected output:
```json
{"status":"ok"}
```

### 3. Open the Workflow Editor
Open **[http://localhost:5678](http://localhost:5678)** in your browser:
1. Complete the one-time owner account setup (email & password).
2. You will be redirected to the n8n workflow canvas.

---

## Connecting Kong Gateway to n8n (Ingress Route)

To expose an n8n webhook through Kong Gateway (port `8088`) with rate limiting and API key authentication:

### 1. Register n8n as a Kong Service
```bash
curl.exe -i -X POST http://localhost:8001/services \
  -d "name=n8n-ingest-service" \
  -d "url=http://host.docker.internal:5678"
```

### 2. Create an Ingestion Route
```bash
curl.exe -i -X POST http://localhost:8001/services/n8n-ingest-service/routes \
  -d "name=n8n-webhook-route" \
  -d "paths[]=/api/v1/telemetry" \
  -d "strip_path=false"
```

*(External webhooks sent to `http://localhost:8088/api/v1/telemetry` will now proxy directly to n8n!)*

---

## Connecting n8n to CDE Pipeline Components

### 1. Path A: Redis Streams (Urgent Alert Lane)
- In your n8n workflow, add a **Redis** node.
- **Connection Host:** `host.docker.internal` (or `imops-redis` if using container network)
- **Port:** `6379`
- **Operation:** Execute Custom Command $\rightarrow$ `XADD stream:urgent * event_id {{ $json.event_id }} severity {{ $json.severity }}`

### 2. Path B: Raw Storage (MinIO / MongoDB)
- Add a **MongoDB** node or **AWS S3 / MinIO** node:
  - **S3 / MinIO Endpoint:** `http://host.docker.internal:9000`
  - **Bucket:** `lake-raw`
  - Write raw payload directly as `.json.gz` or unindexed document.

---

## Stop & Maintenance

- **Stop container:**
  ```bash
  docker compose down
  ```
- **View live logs:**
  ```bash
  docker compose logs -f
  ```
- **Reset n8n data (clean state):**
  ```bash
  docker compose down
  # delete the ./n8n_data directory if you wish to wipe workflow history
  ```
