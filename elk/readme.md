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
│   └── filebeat.yml                # Docker container harvester config
└── scripts/
    ├── deploy_elk.ps1              # One-click startup script (PowerShell)
    ├── deploy_elk.sh               # One-click startup script (Bash)
    ├── enable_kong_logstash.ps1    # Configures Kong tcp-log plugin (PowerShell)
    ├── enable_kong_logstash.sh     # Configures Kong tcp-log plugin (Bash)
    └── verify_elk.ps1              # Checks container status, indices & counts
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

### Step 3: Verify Log Ingestion

Run the verification script:

```powershell
powershell -ExecutionPolicy Bypass -File elk/scripts/verify_elk.ps1
```

Or query Elasticsearch indices directly:

```bash
curl http://localhost:9200/_cat/indices/cde-*?v
```

---

## 5. Accessing Dashboards & Raw Data in Kibana

### Quick Access Links

| View | Direct URL | Description |
| :--- | :--- | :--- |
| 📊 **CDE Platform Overview Dashboard** | **[http://localhost:5601/app/dashboards#/view/cde-platform-overview](http://localhost:5601/app/dashboards#/view/cde-platform-overview)** | Prebuilt charts (volume, distribution) + live raw log stream |
| 🔍 **Raw Data Explorer (Discover)** | **[http://localhost:5601/app/discover](http://localhost:5601/app/discover)** | Dedicated query interface to search, filter, and tail raw JSON documents |
| 📋 **CDE Live Raw Logs Search** | **[http://localhost:5601/app/discover#/view/cde-live-raw-logs](http://localhost:5601/app/discover#/view/cde-live-raw-logs)** | Saved search with timestamp, source, container, and message columns |

---

### How to View Raw Application Logs

#### Method A: Directly from the Dashboard
1. Open the **[CDE Platform Overview Dashboard](http://localhost:5601/app/dashboards#/view/cde-platform-overview)**.
2. Scroll to the **Live Raw Log Stream** panel at the bottom.
3. Click the small **`>` arrow** on the far-left of any row to expand the document.
4. Click the **JSON** tab inside the expanded view to inspect or copy the full, unmutated raw JSON payload.
5. **One-Click Filtering**: Click on any slice of the pie chart or click the `(+)` magnifying glass next to any container name (e.g. `kong-gateway`) to filter the raw log stream instantly to that container.

#### Method B: In the Dedicated "Discover" Tab
1. Open **[http://localhost:5601/app/discover](http://localhost:5601/app/discover)**.
2. Ensure the Data View is set to **`CDE Unified Logs (Kong, n8n, System)`** (`cde-*`).
3. Click any document's **`>` arrow** to view parsed key-value pairs or click **JSON** for the raw format.

---

### Useful Search & Filtering Queries (KQL)

- **Filter by Application / Container:**
  ```kql
  container.name: "kong-gateway"
  ```
  ```kql
  container.name: "n8n-server"
  ```
  ```kql
  container.name: "cde-elasticsearch"
  ```
- **Find all Kong Gateway logs:**
  ```kql
  log_source: "kong-gateway" or log_source: "kong-service"
  ```
- **Find Kong requests with HTTP 4xx or 5xx status:**
  ```kql
  response.status >= 400
  ```
- **Find slow Kong requests (latency > 500ms):**
  ```kql
  latencies.request > 500
  ```
- **Find all n8n workflow logs:**
  ```kql
  log_source: "n8n-workflow-engine" or container.name: "*n8n*"
  ```
- **Find errors across any container:**
  ```kql
  message: (*error* or *fail* or *exception*) or response.status >= 500
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
