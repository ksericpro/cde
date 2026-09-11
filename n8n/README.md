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
