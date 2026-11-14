# CDE Infrastructure Monitoring & Observability (Grafana + Prometheus)

This directory provides the complete multi-container monitoring stack for the Common Data Environment (CDE), modeled after the enterprise monitoring architecture in Hawkeye Infrastructure.

For the full architectural breakdown, dashboard configuration, and troubleshooting guide, see **[Grafana_Prometheus_Monitoring_Setup.md](file:///c:/Projects/cde/grafana/docs/Grafana_Prometheus_Monitoring_Setup.md)**.

---

## 1. Stack Components

| Service | Port | Metric Scope | Source Container |
| :--- | :--- | :--- | :--- |
| **Grafana** | `3000` | Web UI Dashboard & Alert Rules | `cde-grafana` (`grafana/grafana:11.2.0`) |
| **Prometheus** | `9090` | Time-Series TSDB (15-day retention) | `cde-prometheus` (`prom/prometheus:v2.54.1`) |
| **Node Exporter** | `9100` | Host CPU, RAM, Disk I/O, Network | `cde-node-exporter` (`prom/node-exporter:v1.8.2`) |
| **cAdvisor** | `8085` | Container CPU, RAM, Restarts | `cde-cadvisor` (`gcr.io/cadvisor/cadvisor:v0.51.0`) |
| **Kong Plugin** | `8001/metrics` | Ingress RPS, Latencies (P90-P99), 2xx/4xx/5xx | `kong-gateway` (`kong:3.9`) |
| **n8n Engine** | `5678/metrics` | Workflow runs, Success/Fail rates, Durations | `n8n-server` (`docker.n8n.io/n8nio/n8n:latest`) |
| **iMOPS Backend** | `13000/metrics` | API incident throughput, latencies, Node.js lag | External iMOPS server (`10.99.32.54` / `host.docker.internal`) |
| **iMOPS Node** | `9100/metrics` | Host CPU, RAM, Disk, Network | External iMOPS server node-exporter |

---

## 2. Directory Layout

```
grafana/
├── .env.example                                      # Environment variables template
├── .env                                              # Active deployment credentials
├── docker-compose.yml                                # Multi-container stack definition
├── readme.md                                         # Quick reference
├── docs/
│   └── Grafana_Prometheus_Monitoring_Setup.md       # Full setup guide & dashboard instructions
├── prometheus/
│   └── prometheus.yml                                # Prometheus scrape targets configuration
├── provisioning/
│   ├── datasources/
│   │   └── datasources.yaml                          # Auto-provisioned Prometheus datasource
│   └── dashboards/
│       ├── dashboards.yaml                           # Dashboard provider configuration (CDE & iMOPS)
│       └── definitions/
│           ├── cde/
│           │   └── cde_overview.json                 # CDE Overview dashboard
│           └── imops/
│               └── imops_overview.json               # iMOPS External Observability dashboard
└── scripts/
    ├── deploy_monitoring.sh                          # Linux deployment launcher
    ├── deploy_monitoring.ps1                         # Windows deployment launcher
    ├── enable_kong_prometheus.sh                     # Enables Kong prometheus plugin (Linux)
    ├── enable_kong_prometheus.ps1                    # Enables Kong prometheus plugin (PowerShell)
    ├── configure_ufw_monitoring.sh                   # Opens UFW firewall ports on host
    ├── verify_monitoring.sh                          # Verification test script (Bash)
    └── verify_monitoring.ps1                         # Verification test script (PowerShell)
```

---

## 3. Quick Start

### Step 1: Open Firewall Ports (Linux Host)
```bash
sudo ./scripts/configure_ufw_monitoring.sh
```

### Step 2: Deploy Monitoring Stack
```bash
./scripts/deploy_monitoring.sh
```
*Or on Windows:*
```powershell
.\scripts\deploy_monitoring.ps1
```

### Step 3: Enable Kong Prometheus Metrics
```bash
./scripts/enable_kong_prometheus.sh "http://localhost:8001"
```
*Or on Windows:*
```powershell
.\scripts\enable_kong_prometheus.ps1 -KongAdminUrl "http://localhost:8001"
```

### Step 4: Open Dashboards
* **Grafana**: **[http://localhost:3000](http://localhost:3000)** (Default: `admin` / `cdepassword123`)
  * Folder **`CDE Infrastructure & Gateway`**: **CDE - Infrastructure, Kong Gateway & n8n Overview**
  * Folder **`iMOPS Observability`**: **iMOPS - External Infrastructure & API Observability**
* **Prometheus Targets**: **[http://localhost:9090/targets](http://localhost:9090/targets)**

---

## 4. How to Change the iMOPS Target IP

Prometheus handles scraping the external iMOPS host and API. Grafana automatically visualizes whichever targets Prometheus scrapes:

1. Open `prometheus/prometheus.yml`:
   ```yaml
   # Scrape iMOPS External Host Infrastructure (Node Exporter)
   - job_name: 'imops-infra'
     scrape_interval: 15s
     static_configs:
       - targets: ['<NEW_IMOPS_IP>:9100']

   # Scrape iMOPS Application API & Node.js Engine
   - job_name: 'imops-api'
     scrape_interval: 15s
     metrics_path: /metrics
     static_configs:
       - targets: ['<NEW_IMOPS_IP>:13000']
   ```
2. Reload Prometheus:
   ```bash
   docker restart cde-prometheus
   ```
*(No changes are needed in Grafana; the dashboards will automatically display data from the updated IP).*

---

## 5. Exporting Data & Sharing Dashboards in Grafana

### Option 1: Export a Panel's Data to CSV (For Excel / Analysts)
In Grafana (`http://localhost:3000`), CSV data is exported per chart/table:
1. Open either the **CDE - Infrastructure, Kong Gateway & n8n Overview** dashboard or the **iMOPS - External Infrastructure & API Observability** dashboard.
2. Hover over the chart or table you want to export (e.g., *iMOPS API HTTP Status Breakdown* or *n8n Workflow Executions*).
3. Click the **`⋮` (three vertical dots)** icon in the **top-right corner of that panel**.
4. Select **Inspect** $\rightarrow$ **Data**.
5. *(Optional)* If the panel has multiple series, expand **Data options** and select **Series joined by time** and toggle **Formatted data**.
6. Click **Download CSV**.

### Option 2: Share an Interactive Dashboard Snapshot (For External Stakeholders)
To share the entire dashboard with all data points frozen at a point in time (even with people who cannot access your local network or Prometheus):
1. Set the desired time window in the top-right corner (e.g., `Last 1 hour` or `Last 24 hours`).
2. Click **Share** in the **top navigation bar** (next to the dashboard title).
3. Switch to the **Snapshot** tab.
4. Set an **Expire** duration (e.g., `1 Day` or `7 Days`).
5. Click **Publish to snapshots.raintank.io** (generates a public read-only link) or **Local Snapshot** (saves a read-only snapshot on your Grafana instance).

### Option 3: Export the Full Dashboard to PDF (Visual Report)
1. Open the dashboard and click the **TV / Kiosk icon** in the top-right corner (or press **`d` then `k`** on your keyboard) to hide menus and sidebars.
2. Press **`Ctrl + P`** in your browser.
3. Set Destination to **Save as PDF**, Orientation to **Landscape**, and enable **Background graphics**.

### Option 4: Export Dashboard Layout (JSON) or Bulk Prometheus Metrics (CLI)
- **Dashboard JSON:** Click **Share** (top navigation bar) $\rightarrow$ **Export** tab $\rightarrow$ **Save to file** *(or use the versioned JSON files directly in `provisioning/dashboards/definitions/cde/cde_overview.json` and `provisioning/dashboards/definitions/imops/imops_overview.json`)*.
- **Prometheus HTTP API Bulk Export:**
  ```powershell
  # Export 24h of Kong / iMOPS request rates by HTTP status code at 5-minute intervals
  curl.exe -G -s "http://localhost:9090/api/v1/query_range" --data-urlencode "query=sum(rate(kong_http_requests_total[5m])) by (service, code)" --data-urlencode "start=2026-11-02T00:00:00Z" --data-urlencode "end=2026-11-03T00:00:00Z" --data-urlencode "step=5m" -o prom_metrics_export.json
  ```
