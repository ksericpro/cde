# CDE Infrastructure Monitoring & Observability Setup Guide
### Full-Stack Metrics Collection with Prometheus, Grafana, Node Exporter, cAdvisor & Kong Gateway

This guide describes the architecture, deployment, configuration, dashboard visualization, and verification of the monitoring stack in the Common Data Environment (CDE), modeled after enterprise production patterns from Hawkeye Infrastructure.

---

## 1. Overview & Architecture

The CDE monitoring architecture collects real-time metrics across 3 foundational layers:
1. **Host Infrastructure Layer**: CPU, RAM, disk I/O, swap, network throughput, and Linux system load via `node-exporter`.
2. **Container Runtime Layer**: Per-container CPU throttling, memory limits, network socket stats, and restart loops via Google `cAdvisor`.
3. **Edge API Gateway Layer**: Ingress request rates (RPS), P90/P95/P99 latency distribution, HTTP status codes (`2xx`/`4xx`/`5xx`), and upstream service health via the `kong-prometheus` plugin.

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                                 TELEMETRY PRODUCERS                                    │
├──────────────────────────┬──────────────────────────┬──────────────────────────────────┤
│ Host Node Exporter       │ Google cAdvisor          │ Kong API Gateway                 │
│ (:9100/metrics)          │ (:8080/metrics)          │ (:8001/metrics)                  │
│ • CPU / Memory           │ • Per-container CPU      │ • Request Rate (RPS)             │
│ • Disk I/O & Filesystem  │ • Memory Working Set     │ • P90/P95/P99 Latency            │
│ • Host Network In/Out    │ • Container Restarts     │ • HTTP 2xx/4xx/5xx Breakdown     │
└────────────┬─────────────┴────────────┬─────────────┴─────────────────┬────────────────┘
             │                          │                               │
             └──────────────────────────┼───────────────────────────────┘
                                        │ (Scrapes every 15s)
                                        ▼
                         ┌──────────────────────────────┐
                         │ Prometheus Server (:9090)    │
                         │ • TSDB Storage (15-day TTL)  │
                         │ • Scrape Targets & Rules     │
                         └──────────────┬───────────────┘
                                        │ (PromQL Queries)
                                        ▼
                         ┌──────────────────────────────┐
                         │ Grafana Dashboards (:3000)   │
                         │ • Auto-provisioned Source    │
                         │ • Real-Time Visual Panels    │
                         │ • Proactive Alert Rules      │
                         └──────────────────────────────┘
```

---

## 2. Port & Service Matrix

| Service | Container Name | Host Port | Internal Port | Purpose |
| :--- | :--- | :--- | :--- | :--- |
| **Grafana** | `cde-grafana` | `3000` | `3000` | Web dashboard UI & visualization engine |
| **Prometheus** | `cde-prometheus` | `9090` | `9090` | Time-series database & metrics scraper |
| **Node Exporter** | `cde-node-exporter` | `9100` | `9100` | Linux host hardware & OS kernel metrics |
| **cAdvisor** | `cde-cadvisor` | `8080` | `8080` | Docker container resource monitoring |
| **Kong Admin** | `kong-gateway` | `8001` | `8001` | Scrape target for `/metrics` endpoint |

---

## 3. Directory Layout & Provisioning Structure

```
grafana/
├── .env.example                                      # Environment variables template
├── .env                                              # Active deployment credentials
├── docker-compose.yml                                # Multi-container stack definition
├── readme.md                                         # Quick-reference overview
├── docs/
│   └── Grafana_Prometheus_Monitoring_Setup.md       # Comprehensive implementation guide
├── prometheus/
│   └── prometheus.yml                                # Scrape jobs and target definitions
├── provisioning/
│   ├── datasources/
│   │   └── datasources.yaml                          # Auto-connects Prometheus datasource
│   └── dashboards/
│       ├── dashboards.yaml                           # Dashboard discovery provider
│       └── definitions/
│           └── cde_overview.json                     # Pre-packaged CDE Overview dashboard
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

## 4. Step-by-Step Installation & Deployment

### Step 1: Configure UFW Firewall (Linux VM Server)
If host firewall (`ufw`) is active on the Linux server (e.g. `isems@sov-webapp`), run:
```bash
cd /path/to/cde/grafana/scripts
chmod +x *.sh
sudo ./configure_ufw_monitoring.sh
```
This opens ports `3000` (Grafana), `9090` (Prometheus), `9100` (Node Exporter), and `8080` (cAdvisor).

### Step 2: Deploy Prometheus and Grafana Stack
Run the deployment script:
```bash
./scripts/deploy_monitoring.sh
```
*Or on Windows PowerShell:*
```powershell
.\scripts\deploy_monitoring.ps1
```

### Step 3: Enable Prometheus Metrics Plugin on Kong Gateway
Kong does not expose `/metrics` until the `prometheus` plugin is enabled. Run:
```bash
./scripts/enable_kong_prometheus.sh "http://localhost:8001"
```
*Or on Windows PowerShell:*
```powershell
.\scripts\enable_kong_prometheus.ps1 -KongAdminUrl "http://localhost:8001"
```

Verify that Kong `/metrics` returns Prometheus text metrics:
```bash
curl -i http://localhost:8001/metrics
```

### Step 4: Verify Scrape Targets in Prometheus
1. Open Prometheus UI in browser: **[http://localhost:9090/targets](http://localhost:9090/targets)**.
2. Confirm all endpoints show status **UP**:
   - `prometheus` (`localhost:9090`)
   - `node-exporter` (`cde-node-exporter:9100`)
   - `cadvisor` (`cde-cadvisor:8080`)
   - `kong-gateway` (`host.docker.internal:8001` or `kong-gateway:8001`)

---

## 5. Grafana Dashboard Visualizations

### 5.1 Out-of-the-box CDE Overview Dashboard
The stack automatically provisions the dashboard **"CDE - Infrastructure & Kong Gateway Overview"** under folder `CDE Infrastructure & Gateway`:
1. Log in to Grafana at **[http://localhost:3000](http://localhost:3000)** (Default: `admin` / `cdepassword123`).
2. Navigate to **Dashboards** $\rightarrow$ **CDE Infrastructure & Gateway** $\rightarrow$ **CDE - Infrastructure & Kong Gateway Overview**.
3. The dashboard features:
   - **Host Gauges**: CPU Busy %, RAM Usage %, Root Disk Used %, Network I/O throughput.
   - **Docker Containers**: Per-container CPU percentage and memory working set (`kong-gateway`, `cde-n8n`, `kong-db`, etc.).
   - **Kong Gateway**: Requests per second (RPS), Latency quantiles (P90, P95, P99), and HTTP status codes (`2xx`, `4xx`, `5xx`).

### 5.2 Importing Community Standard Dashboards (Hawkeye Pattern)
As recommended in enterprise setups, you can also import world-class community dashboards via Grafana ID:

1. **Dashboard 1860 (Node Exporter Full)**:
   - Go to **Dashboards** $\rightarrow$ **New** $\rightarrow$ **Import**.
   - Enter ID **`1860`** and click **Load**.
   - Select datasource **`Prometheus`** and click **Import**.
   - Provides exhaustive OS-level metrics, disk temperature, IOPS, and socket details.

2. **Dashboard 7424 (Kong Official Dashboard)**:
   - Go to **Dashboards** $\rightarrow$ **New** $\rightarrow$ **Import**.
   - Enter ID **`7424`** and click **Load**.
   - Select datasource **`Prometheus`** and click **Import**.
   - Visualizes detailed Kong route-by-route latencies, upstream health checks, and proxy cache hit rates.

3. **Dashboard 14282 (Docker cAdvisor)**:
   - Go to **Dashboards** $\rightarrow$ **New** $\rightarrow$ **Import**.
   - Enter ID **`14282`** and click **Load**.
   - Visualizes container memory limits vs reservations and CPU shares.

---

## 6. Verification & Troubleshooting

Run the automated verification script:
```bash
./scripts/verify_monitoring.sh
```
*Or in PowerShell:*
```powershell
.\scripts\verify_monitoring.ps1
```

### Common Troubleshooting Scenarios

#### 1. Kong Target Shows "DOWN" in Prometheus
* **Cause**: Prometheus cannot reach Kong Admin API on port `8001`.
* **Fix**: Ensure `extra_hosts: ["host.docker.internal:host-gateway"]` is present in `grafana/docker-compose.yml`, or that Kong Gateway is attached to `cde-network`.

#### 2. Prometheus Target Returns 404 for `/metrics`
* **Cause**: The `prometheus` plugin has not been enabled on Kong.
* **Fix**: Run `./scripts/enable_kong_prometheus.sh http://localhost:8001`.

#### 3. Permission Denied on Prometheus / Grafana Volume Mounts
* **Cause**: Docker container running as non-root user cannot write to host volume.
* **Details**: Prometheus runs as user `nobody` (UID `65534`), Grafana runs as user `grafana` (UID `472`).
* **Fix**: Run:
  ```bash
  sudo chown -R 65534:65534 /path/to/prometheus_data
  sudo chown -R 472:472 /path/to/grafana_data
  ```
  *(Note: Named Docker volumes managed by docker-compose handle this automatically).*
