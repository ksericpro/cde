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
| **cAdvisor** | `8080` | Container CPU, RAM, Restarts | `cde-cadvisor` (`gcr.io/cadvisor/cadvisor:v0.49.1`) |
| **Kong Plugin** | `8001/metrics` | Ingress RPS, Latencies (P90-P99), 2xx/4xx/5xx | `kong-gateway` (`kong:3.9`) |

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
│       ├── dashboards.yaml                           # Dashboard provider configuration
│       └── definitions/
│           └── cde_overview.json                     # Auto-imported CDE Overview dashboard
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
  * Pre-provisioned Dashboard: **CDE - Infrastructure & Kong Gateway Overview**
  * Recommended Community Dashboards: ID **`1860`** (Node Exporter Full) & ID **`7424`** (Kong Official)
* **Prometheus Targets**: **[http://localhost:9090/targets](http://localhost:9090/targets)**
* **Verification Script**:
  ```bash
  ./scripts/verify_monitoring.sh
  ```
