# CDE Centralized Logging (ELK Stack)

This directory contains the Docker Compose stack, Logstash pipelines, Filebeat collectors, and automated setup scripts for centralizing, indexing, and visualizing logs across **Kong API Gateway**, **n8n Workflow Engine**, and CDE platform services.

---

## 1. Architecture & Log Flow

```
                      ┌────────────────────────────────────────┐
                      │            Log Sources                 │
                      └──────────────────┬─────────────────────┘
                                         │
             ┌───────────────────────────┴───────────────────────────┐
             │                                                       │
             ▼                                                       ▼
   [ Kong API Gateway ]                                    [ n8n Workflow Server ]
 (tcp-log plugin: JSON)                              (stdout / stderr container stream)
             │                                                       │
             │ :5000 (TCP/JSON)                                      │ /var/lib/docker/containers/*
             │                                                       ▼
             │                                              [ cde-filebeat :8.14.3 ]
             │                                              (Docker container input:
             │                                               filters cde-*, n8n-*, kong-*)
             │                                                       │
             │                                                       │ :5044 (Beats)
             ▼                                                       ▼
   ┌─────────────────────────────────────────────────────────────────────────┐
   │                         cde-logstash :8.14.3                            │
   │  - Parses JSON from Kong Gateway                                        │
   │  - Normalizes fields & adds metadata (log_source, tags)                 │
   │  - Dynamic index routing by source (drops non-CDE containers)           │
   └────────────────────────────────────┬────────────────────────────────────┘
                                        │
                                        │ HTTP :9200
                                        ▼
   ┌─────────────────────────────────────────────────────────────────────────┐
   │                      cde-elasticsearch :8.14.3                          │
   │  - Indices:                                                             │
   │    • cde-kong-logs-YYYY.MM.dd                                           │
   │    • cde-n8n-logs-YYYY.MM.dd                                            │
   │    • cde-system-logs-YYYY.MM.dd                                         │
   └────────────────────────────────────┬────────────────────────────────────┘
                                        │
                                        │ Web :5601
                                        ▼
   ┌─────────────────────────────────────────────────────────────────────────┐
   │                          cde-kibana :8.14.3                             │
   │  - Preconfigured Data View: cde-*                                       │
   │  - Discover view: search by path, latency, status, error                │
   └─────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Ports, Endpoints & Direct Links

| Service / Interface | Internal Host / Port | External / Browser URL | Purpose |
| :--- | :--- | :--- | :--- |
| **Elasticsearch** | `cde-elasticsearch:9200` | `http://localhost:9200` | REST API, search, index management |
| **Kibana Web UI** | `cde-kibana:5601` | [http://localhost:5601](http://localhost:5601) | Main Kibana landing page |
| 📊 **CDE Platform Dashboard** | `cde-kibana:5601` | [http://localhost:5601/app/dashboards#/view/cde-platform-overview](http://localhost:5601/app/dashboards#/view/cde-platform-overview) | **Direct Link**: Overview charts + live log table |
| 🔍 **Raw Data (Discover)** | `cde-kibana:5601` | [http://localhost:5601/app/discover](http://localhost:5601/app/discover) | **Direct Link**: Query, filter, and tail raw JSON logs |
| **Logstash (Kong TCP)** | `cde-logstash:5000` | `localhost:5000` | Kong `tcp-log` ingress endpoint |
| **Logstash (Filebeat)** | `cde-logstash:5044` | `localhost:5044` | Beats ingress for container logs |
| **Logstash API** | `cde-logstash:9600` | `localhost:9600` | Logstash monitoring & pipeline API |

---

## 3. Directory Layout

```
elk/
├── docker-compose.yml              # Single-node ELK + Filebeat compose stack
├── readme.md                       # Documentation & runbook
├── logstash/
│   ├── config/
│   │   └── logstash.yml            # Pipeline settings & monitoring
│   └── pipeline/
│       └── logstash.conf           # Inputs (5000 TCP, 5044 Beats) & routing logic
├── filebeat/
│   ├── filebeat.yml                # Docker container harvester config
│   └── docker_sock_streamer.js     # Real-time Docker Socket log streamer (supports Docker Desktop 'local' driver)
└── scripts/
    ├── deploy_elk.ps1                  # One-click startup script (PowerShell)
    ├── deploy_elk.sh                   # One-click startup script (Bash)
    ├── enable_kong_logstash.ps1        # Configures Kong tcp-log plugin (PowerShell)
    ├── enable_kong_logstash.sh         # Configures Kong tcp-log plugin (Bash)
    ├── provision_kibana_dashboard.ps1  # Provisions CDE & iMOPS Kibana dashboard and saved searches
    ├── sync_imops_logs.ps1             # Optional one-time historical backfill of iMOPS container logs
    └── verify_elk.ps1                  # Checks container status, indices & counts
```

---

## 4. Quick Start & Deployment

### Step 1: Launch ELK Stack

```powershell
powershell -ExecutionPolicy Bypass -File elk/scripts/deploy_elk.ps1
```

_Or via Docker Compose directly:_

```bash
docker compose -f elk/docker-compose.yml up -d
```

### Step 2: Configure Kong Gateway Log Shipping

Run the provisioning script to register the global `tcp-log` plugin on Kong Admin API:

```powershell
powershell -ExecutionPolicy Bypass -File elk/scripts/enable_kong_logstash.ps1
```

_Or via cURL directly:_

```bash
curl -X POST http://localhost:8001/plugins \
  -d "name=tcp-log" \
  -d "config.host=cde-logstash" \
  -d "config.port=5000" \
  -d "config.tls=false"
```

### Step 3: Provision Kibana Dashboard & iMOPS Saved Searches

```powershell
# Provision Kibana dashboard and iMOPS saved searches
powershell -ExecutionPolicy Bypass -File elk/scripts/provision_kibana_dashboard.ps1
```
*(Note: The `cde-docker-log-streamer` container in `elk/docker-compose.yml` automatically streams live logs from `imops-backend` (`localhost:13000`), `imops-worker`, `imops-frontend`, `n8n-*`, and `kong-*` in real time via `/var/run/docker.sock`—no manual syncing required).*

### Step 4: Verify Log Ingestion

Run the verification script:

```powershell
powershell -ExecutionPolicy Bypass -File elk/scripts/verify_elk.ps1
```

Or query Elasticsearch indices directly:

```bash
curl http://localhost:9200/_cat/indices/cde-*?v
```

---

## 5. Accessing Dashboards, Filtering & Exporting Data in Kibana

### Quick Access Links

| View | Direct URL | Description |
| :--- | :--- | :--- |
| 📊 **CDE Platform Overview Dashboard** | **[http://localhost:5601/app/dashboards#/view/cde-platform-overview](http://localhost:5601/app/dashboards#/view/cde-platform-overview)** | Prebuilt charts (volume, iMOPS services, HTTP 200 vs 4xx/5xx status) + live iMOPS & CDE log tables |
| 🚨 **iMOPS API & Incident Logs (Success & Error)** | **[http://localhost:5601/app/discover#/view/imops-live-logs](http://localhost:5601/app/discover#/view/imops-live-logs)** | Pre-filtered saved search for all iMOPS requests (`service.name: *imops*`) with route, status, and latency columns |
| 📋 **CDE Live Raw Logs Search** | **[http://localhost:5601/app/discover#/view/cde-live-raw-logs](http://localhost:5601/app/discover#/view/cde-live-raw-logs)** | Unified saved search across Kong, iMOPS, n8n, and CDE containers |
| 🔍 **Raw Data Explorer (Discover)** | **[http://localhost:5601/app/discover](http://localhost:5601/app/discover)** | Dedicated query interface to search, filter, and tail raw JSON documents |

---

### What ELK Ingests vs. What Is Filtered Out

Based on `filebeat/filebeat.yml` and `logstash/pipeline/logstash.conf`, ELK uses prefix rules (`^cde-`, `^n8n-`, `^kong-`, `^imops-`) and Kong's `tcp-log` stream:

| Application / Source | Mechanism | Ingested? | What Is Captured | Target Index |
| :--- | :--- | :---: | :--- | :--- |
| **iMOPS Application (`localhost:13000`)** | `cde-docker-log-streamer` + Filebeat (`imops-backend`, `imops-worker`, `imops-frontend`, `imops-mongodb`, `imops-redis`) | ✅ Yes (Auto Real-Time) | Direct application `stdout`/`stderr` logs (`[DEBUG]`, `[INFO]`, `[ERROR]`, incident processing, DB/Redis logs) streamed live via `/var/run/docker.sock` | `cde-imops-logs-*` |
| **Kong API Gateway & iMOPS Traffic** | Kong `tcp-log` plugin (`:5000`) | ✅ Yes | Every API request to `localhost:13000` via Kong: `service.name`, `route.name`, `request.uri`, `response.status`, `upstream_status`, `latencies.proxy`, `client_ip` | `cde-kong-logs-*` |
| **Kong Stack Containers** | Filebeat (`kong-gateway`, `kong-db`, `kong-redis`) | ✅ Yes | Container `stdout`/`stderr` (Nginx worker logs, Postgres, Redis) | `cde-kong-logs-*` |
| **n8n Workflow Engine** | Filebeat (`n8n-server`, `n8n-proxy`) | ✅ Yes | Container `stdout`/`stderr` (startup, webhook exceptions, Nginx access logs) | `cde-n8n-logs-*` |
| **CDE Monitoring & Infra** | Filebeat (`cde-prometheus`, `cde-grafana`, `cde-cadvisor`, `cde-node-exporter`, `cde-elasticsearch`, `cde-kibana`) | ✅ Yes | Container `stdout`/`stderr` health and runtime logs | `cde-system-logs-*` |
| **External Host / Non-CDE Containers** | Any container not starting with `cde-`, `n8n-`, `kong-`, or `imops-` | ❌ Dropped | Dropped by `filebeat.yml` and `logstash.conf` (`drop { }`) unless added to the filter rules | — |

---

### Useful Search & Filtering Queries (KQL)

Paste any of the following into the top KQL search bar (`Filter your data using KQL syntax`) in Kibana **Discover** or **Dashboard**:

#### A. iMOPS Application (`localhost:13000`) & API Traffic
- **All iMOPS Logs (Direct `imops-backend` `:13000` App Logs + Kong API Calls):**
  ```kql
  log_source: "imops-application" or container.name: imops-* or (service.name: *imops* and not service.name: *n8n*)
  ```
- **Only Direct `imops-backend` (`localhost:13000`) Application Logs:**
  ```kql
  container.name: "imops-backend"
  ```
- **Only Direct `imops-worker` Background Job Logs:**
  ```kql
  container.name: "imops-worker"
  ```
- **Only iMOPS API SUCCESS (`200–299`):**
  ```kql
  service.name: *imops* and not service.name: *n8n* and response.status >= 200 and response.status < 300
  ```
- **Only iMOPS ERRORS (API `400+` or `imops-backend` App Errors):**
  ```kql
  (service.name: *imops* and not service.name: *n8n* and response.status >= 400) or (container.name: imops-* and message: (*ERROR* or *WARN* or *fail* or *Exception*))
  ```

#### B. Combined iMOPS + n8n (Success vs. Error)
- **All iMOPS & n8n Logs:**
  ```kql
  service.name: *imops* or log_source: "n8n-workflow-engine" or request.uri: (*proscalar* or *va*)
  ```
- **Only iMOPS & n8n SUCCESS (`200–299`):**
  ```kql
  (service.name: *imops* or request.uri: (*proscalar* or *va*)) and response.status >= 200 and response.status < 300
  ```
- **Only iMOPS & n8n ERRORS (`4xx`/`5xx` or n8n Exceptions):**
  ```kql
  ((service.name: *imops* or request.uri: (*proscalar* or *va*)) and response.status >= 400) or (log_source: "n8n-workflow-engine" and message: (*error* or *fail* or *exception* or *500* or *502*))
  ```

#### C. General Container & Performance Filters
- **Filter by Container:**
  ```kql
  container.name: "kong-gateway"
  ```
  ```kql
  container.name: "n8n-server"
  ```
- **Find slow Kong / iMOPS requests (latency > 500ms):**
  ```kql
  latencies.request > 500
  ```

---

### How to View & Export Raw Data (CSV & JSON) in Kibana

#### 1. Which Columns Contain the Log Message Body & Status?
When viewing or exporting logs in Kibana Discover, use these fields from the left sidebar:

| Field / Column Name | What It Contains | Applies To |
| :--- | :--- | :--- |
| **`_source`** *(default if no columns added)* | The entire raw JSON document for that row | All logs |
| **`message`** | **The raw text log body** (stdout/stderr messages, error stack traces) | All Docker containers (`n8n-server`, `kong-gateway`, `cde-*`) |
| **`service.name`** | Target Kong service (`imops-sicc-incident-service`, `imops-proscalar-n8n-service`, `imops-dors-incident-service`) | Kong / iMOPS API logs |
| **`request.method`** & **`request.uri`** | HTTP method (`POST`/`GET`) and endpoint called (e.g. `/va/sov-38alt-...`, `/api/proscalar/webhook`) | Kong / iMOPS API logs |
| **`response.status`** & **`upstream_status`** | HTTP status code (**`200` = Success**, **`400`/`401`/`429`/`500`/`502` = Error**) | Kong / iMOPS API logs |
| **`latencies.proxy`** / **`latencies.request`** | Upstream iMOPS processing time and total request latency (in ms) | Kong / iMOPS API logs |
| **`container.name`** | Docker container name (`n8n-server`, `kong-gateway`, `cde-cadvisor`) | Filebeat container logs |

#### 2. Export Logs to a CSV File
1. Open **[iMOPS Live Logs](http://localhost:5601/app/discover#/view/imops-live-logs)** or **[CDE Live Raw Logs](http://localhost:5601/app/discover#/view/cde-live-raw-logs)** in Kibana Discover.
2. *(Optional)* Apply any KQL filter in the top search bar and add/remove columns via the **`+`** icon on the left sidebar.
3. Click **Save** in the top-right corner *(Kibana requires the search to be saved before enabling CSV export)*.
4. Click **Share** (top-right toolbar) $\rightarrow$ **CSV Reports** $\rightarrow$ **Generate CSV**.
5. Click **Download** on the toast notification in the bottom-right corner *(or download anytime from **☰ Menu $\rightarrow$ Stack Management $\rightarrow$ Alerts and Insights $\rightarrow$ Reporting**)*.

#### 3. View or Export Raw JSON Payloads
- **Single Log Row:** Click the **`⇄` / `>` expand icon** on the far-left of any row in the table, then switch to the **JSON** tab to inspect or copy the full raw JSON document.
- **Bulk JSON Export (No Save Required):** In Discover, click **Inspect** (top-right toolbar) $\rightarrow$ set the dropdown to **View: Requests** $\rightarrow$ click the **Response** tab to copy the raw Elasticsearch JSON array.
- **CLI Bulk JSON Export:**
  ```powershell
  curl.exe -s "http://localhost:9200/cde-kong-logs-*/_search?size=10000" -H "Content-Type: application/json" -d "{\"sort\":[{\"@timestamp\":\"desc\"}]}" -o kong_imops_logs_export.json
  ```

---

## 6. Log Schemas

### Kong Gateway Log Record (`cde-kong-logs-*`)

```json
{
  "@timestamp": "2026-10-22T06:46:05.043Z",
  "log_source": "kong-gateway",
  "client_ip": "172.21.0.1",
  "request": {
    "method": "POST",
    "uri": "/api/proscalar/webhook",
    "id": "45cec47f137a6e4c8b2ae65b64e7ab67",
    "headers": {
      "content-type": "application/json",
      "user-agent": "curl/8.21.0"
    }
  },
  "response": {
    "status": 401,
    "size": 432
  },
  "latencies": {
    "kong": 6,
    "request": 6,
    "proxy": -1
  },
  "service": {
    "name": "imops-proscalar-n8n-service",
    "host": "n8n-server",
    "port": 5678
  },
  "route": {
    "name": "proscalar-webhook-route",
    "paths": ["/api/proscalar/webhook"]
  }
}
```

### n8n Workflow Log Record (`cde-n8n-logs-*`)

```json
{
  "@timestamp": "2026-10-22T06:44:10.343Z",
  "log_source": "n8n-workflow-engine",
  "container": {
    "name": "n8n-server",
    "image": { "name": "docker.n8n.io/n8nio/n8n:latest" }
  },
  "stream": "stdout",
  "message": "Bad request - please check your parameters"
}
```

---

## 7. Creating Kibana Dashboards

Kibana Dashboards allow you to assemble multiple visualizations, metrics, and search tables into a single real-time monitoring pane.

> **Pre-configured Dashboard Available:**
> A dashboard has already been created for this stack: **[CDE Platform Overview](http://localhost:5601/app/dashboards#/view/cde-platform-overview)**.
> It includes Log Volume Over Time, Service Log Distribution, and a Live Raw Log Stream. You can view it directly or follow the steps below to customize or build new dashboards.

### Step 1: Open the Dashboard Workspace

1. Navigate to **[http://localhost:5601](http://localhost:5601)** in your browser.
2. Click the **☰ (Menu)** icon on the top-left navigation panel.
3. Under the **Analytics** group, select **Dashboard**.
4. Click the blue **Create dashboard** button in the upper right.

### Step 2: Build Visualizations with Kibana Lens

Click **Create visualization** to launch Kibana Lens (the drag-and-drop visualization builder). Verify that the top-left Data View dropdown is set to **`cde-*`** (**CDE Unified Logs**).

Below are recommended panel recipes tailored for CDE logs:

#### Panel 1: Log Volume Over Time (Bar / Area Chart)

_Visualizes ingestion rate and activity spikes across all CDE components._

- **Chart Type**: Stacked Bar (or Stacked Area) in the top toolbar.
- **Horizontal Axis**: Drag **`@timestamp`** to the canvas.
- **Vertical Axis**: Count of records (default).
- **Break down by**: Drag **`log_source.keyword`** into the _Break down by_ field on the right sidebar.
- Click **Save and return** in the top-right header.

#### Panel 2: Kong HTTP Status Code Breakdown (Donut Chart)

_Identifies API success rates (2xx), client errors (4xx), and gateway issues (5xx)._

- Click **Create visualization**.
- **Chart Type**: Switch chart type in the top bar to **Donut**.
- **Slice by**: Drag **`response.status`** into the canvas.
- **Filter (Optional)**: In the KQL bar at top, enter `log_source: "kong-gateway"` to isolate API Gateway responses.
- Click **Save and return**.

#### Panel 3: Log Distribution by Service (Treemap / Pie)

_Highlights which container or service is generating the most log volume._

- Click **Create visualization**.
- **Chart Type**: Select **Donut** or **Treemap**.
- **Slice by**: Drag **`container.name.keyword`** into the canvas.
- Click **Save and return**.

#### Panel 4: Gateway API Latency by Route (Bar Chart)

_Surfaces average response time and upstream latency for each API endpoint._

- Click **Create visualization**.
- **Chart Type**: **Bar horizontal**.
- **Horizontal Axis**: Select **`latencies.request`** -> change aggregation to **Average**.
- **Break down by**: Drag **`route.name.keyword`** (or `request.uri.keyword`).
- Click **Save and return**.

#### Panel 5: Real-Time Error & Event Stream (Data Table)

_Displays actionable logs with immediate error visibility._

- Click **Create visualization**.
- **Chart Type**: Select **Table**.
- **Columns**: Add the following fields:
  1. `@timestamp`
  2. `log_source`
  3. `container.name`
  4. `response.status` (for Kong)
  5. `message`
- In the top KQL search bar, you can set a filter such as `message: (*error* or *fail* or *exception*) or response.status >= 400` to make an error-only panel, or leave blank for all logs.
- Click **Save and return**.

---

### Step 3: Arrange, Resize & Save

1. **Rearrange**: Drag panel headers to reposition cards on the layout grid.
2. **Resize**: Drag the bottom-right corner of any panel to expand or shrink it.
3. **Time Picker**: In the top-right corner, select your default monitoring window (e.g. `Last 15 minutes` with auto-refresh `10s`).
4. **Save**: Click **Save** in the top navigation bar:
   - **Title**: Enter `CDE Platform Overview` (or preferred name).
   - **Description**: `Unified telemetry and error logs across Kong API Gateway, n8n, and CDE services`.
   - Check **Store time with dashboard** if you want the dashboard to always open with the selected time window.
   - Click **Save**.
