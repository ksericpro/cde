# n8n Workflow Ingestion Engine (CDE)

This module deploys **n8n** alongside an **SSL-terminating Nginx reverse proxy** as the primary Orchestration & Ingestion Engine for the Common Data Environment (CDE), following the enterprise setup in `C:\Projects\ZAARR-DTE\taylor-imops-lite`.

---

## Architecture Overview

```
                                      +---------------------------------------------+
                                      |              cde-network                    |
  Browser / Web App                   |                                             |
  https://localhost:5678              |   +-------------------+                     |
  ------------------------> [Port 5678] ->|     n8n-proxy     |                     |
                                      |   |   (Nginx Alpine)  |                     |
                                      |   +---------+---------+                     |
                                      |             | proxy_pass http://n8n:5678    |
                                      |             v                               |
                                      |   +-------------------+                     |
                                      |   |    n8n-server     |                     |
                                      |   | (Workflow Engine) |                     |
                                      |   +-------------------+                     |
                                      +---------------------------------------------+
```

### Key Features
1. **SSL Termination**: Nginx terminates HTTPS using self-signed TLS certificates (`docker/ssl`).
2. **Branded Theme & Logo Injection**: Injects `docker/custom-theme.css` into the n8n UI on the fly via Nginx `sub_filter`, displaying the custom **Loop Workflow Engine** logo and applying the dark slate/teal palette while hiding unwanted enterprise/cloud upsell menus.
3. **iFrame Embedding**: Strips `X-Frame-Options` and rewrites cookies with `SameSite=None; Secure` so n8n can be embedded seamlessly in CDE web portal dashboards without cross-origin blocking.
4. **WebSocket & SSE Forwarding**: Full streaming support for live execution canvas updates.

---

## Port Allocations & Endpoints

| Service | Port | Protocol | Description | URL |
| :--- | :--- | :--- | :--- | :--- |
| **n8n Automation Control Panel** | **`5678`** | **HTTPS** | Web UI with custom Loop branding | **[https://localhost:5678](https://localhost:5678)** |
| **Webhook Receiver** | **`5678`** | **HTTPS** | Workflow webhook listener | `https://localhost:5678/webhook/...` |
| **Via Kong Gateway** | **`8088`** | HTTP | Public ingress reverse-proxied through Kong | `http://localhost:8088/n8n/` |

> [!NOTE]
> **Browser Security Notice (HTTPS)**:
> When opening `https://localhost:5678` for the first time, your browser may show a self-signed certificate warning (*"Your connection is not private"*). Click **Advanced $\rightarrow$ Proceed to localhost (unsafe)** to continue.

---

## Quick Start

### 1. Launch Containers
From the `c:\Projects\cde\n8n` directory:

```bash
docker compose up -d
```

### 2. Verify Container Health
```bash
docker compose ps
```
Both `n8n-server` and `n8n-proxy` should report status `Up`.

Check health via curl:
```bash
curl.exe -k https://localhost:5678/healthz
```
Expected output:
```json
{"status":"ok"}
```

### 3. Import Workflow

The unified workflow is located in `workflows/proscalar_ingestion_workflow.json`. It dynamically resolves the destination iMOPS API via the `BACKEND_API` environment variable configured in `.env` (or `.env.taylor`).

#### Method A: Via Web UI
1. Open **`https://<N8N_HOST>:5678`** in browser.
2. Go to **Workflows** $\rightarrow$ Click `...` menu (top right) $\rightarrow$ **Import from File**.
3. Select `workflows/proscalar_ingestion_workflow.json`.
4. Turn on the **Active** toggle (top-right, green) and click **Save**.

#### Method B: Via CLI
```bash
docker cp workflows/proscalar_ingestion_workflow.json n8n-server:/tmp/workflow.json
docker exec n8n-server n8n import:workflow --input=/tmp/workflow.json
docker exec n8n-server n8n publish:workflow --id=proscalar-pipeline-v1
docker restart n8n-server
```

---

### 4. Configure Kong Gateway Service to Target n8n

Kong forwards incoming webhooks (`:8088/api/proscalar/webhook`) to n8n (`:5678/webhook/proscalar`).

#### Via Kong Manager UI (`http://<KONG_HOST>:8002`):
1. Navigate to **Gateway Services** $\rightarrow$ click **`imops-proscalar-n8n-service`** $\rightarrow$ click **Edit**.
2. Set Service Endpoint:
   - **Protocol:** `http`
   - **Host:** `n8n-server` *(or `10.99.32.55`)*
   - **Port:** `5678`
   - **Path:** `/webhook/proscalar`
3. Click **Save**.

#### Via CLI:
```bash
curl -i -X PATCH "http://localhost:8001/services/imops-proscalar-n8n-service" \
  -H "Content-Type: application/json" \
  -d '{"protocol":"http","host":"n8n-server","port":5678,"path":"/webhook/proscalar"}'
```

---

## Directory Structure

```
n8n/
├── docker-compose.yml              # Multi-container orchestration (n8n + n8n-proxy)
├── .env                            # Environment variables (HTTPS, cookies, encryption key)
├── .env.example                    # Sample environment template
├── README.md                       # Architecture & runbook documentation
├── docker/
│   ├── nginx.n8n.conf              # Reverse proxy configuration with sub_filter injection
│   ├── custom-theme.css            # Dark slate/teal branding & logo replacement styles
│   └── ssl/                        # SSL certificates & keys (localhost / tayloruniversity)
├── docs/
│   ├── Workflow_engine_logo_loop_202607111220.png # Loop engine logo
│   ├── favicon_loop.png            # Favicon
│   └── solar-onc-pipeline-workflow.json # Example pipeline workflow template
└── n8n_data/                       # Persistent database & workflow configuration
```

## Troubleshooting & Encryption Key Management

For full details, see the dedicated [Troubleshooting Runbook](file:///c:/Projects/cde/n8n/docs/troubleshooting_encryption_keys.md).

### 1. "Mismatching encryption keys"
**Symptom:** `Error: Mismatching encryption keys. The encryption key in the settings file /root/.n8n/config does not match the N8N_ENCRYPTION_KEY env var.`  
**Cause:** `n8n_data/config` has a different key than `N8N_ENCRYPTION_KEY` in `.env`.  
**Resolution:**
```bash
# Option A: Delete config and let n8n use the key from .env
rm -f n8n_data/config
docker compose down
docker compose up -d

# Option B: Set N8N_ENCRYPTION_KEY in .env to match n8n_data/config:
# N8N_ENCRYPTION_KEY=cde-n8n-secret-encryption-key-2026-cde-pipeline
```

### 2. "Deployment key 'signing.hmac' cannot be read"
**Symptom:** `Error: Deployment key 'signing.hmac' cannot be read with this instance encryption key`  
**Cause:** `database.sqlite` was encrypted with an older/different encryption key than the current one.  
**Resolution (Clean DB Reset for Fresh Setup):**
```bash
docker compose down
rm -f n8n_data/database.sqlite*
rm -f n8n_data/config
docker compose up -d
```
*(After restart, complete owner setup at `https://<HOST>:5678` and import workflows from `n8n/workflows/`)*.

### 3. Deploying to Remote Server IP (e.g., `10.99.32.55`)
In `n8n/.env`:
```env
N8N_HOST=10.99.32.55
N8N_WEBHOOK_URL=https://10.99.32.55:5678/
```
Restart with `docker compose down && docker compose up -d`. Access the UI at `https://10.99.32.55:5678`.

---

## Reset & Utility Commands

### Reset n8n User Accounts
```bash
docker exec -it n8n-server n8n user-management:reset
docker restart n8n-server
```

### Clean State / Rebuild
```bash
docker compose down
# To completely reset workflows and credentials:
# Remove-Item -Recurse -Force ./n8n_data/*
docker compose up -d
```

