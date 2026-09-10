# Kong Gateway - Future Roadmap & Observability Architecture

This document details the architectural roadmap, enterprise-grade observability patterns, and production hardening strategies for **Kong Gateway OSS 3.9** within the Common Data Environment (CDE).

---

## 1. Executive Summary & Problem Statement

While Kong Gateway OSS handles perimeter authentication (`basic-auth`, `acl`), request throttling (`rate-limiting`), and payload transformation (`post-function` Lua scripts) with sub-millisecond proxy latency, several operational requirements are scheduled for subsequent implementation:

1. **Request/Response Inspection in OSS:** Kong Manager OSS (`http://localhost:8002`) functions purely as a configuration control plane. Visual audit inspection of incoming payloads and backend responses is an Enterprise/Konnect feature.
2. **Upstream Circuit Breaking:** Graceful degradation when the downstream iMOPS backend undergoes deployment or connection limits.
3. **Declarative GitOps (decK):** Version-controlling all services, routes, and plugins in Git rather than relying on manual curl/UI changes.
4. **Perimeter Security Hardening:** Transitioning from HTTP to HTTPS/TLS (`8443`) and locking down ingress to camera subnets.
5. **Centralized Telemetry:** Prometheus metrics scraping and Grafana dashboards for throughput and latency alerting.

---

## 2. Architecture: End-to-End Ingress & Audit Flow

```
                                  [ CCTV / Edge VA Camera ]
                                              │
                                              ▼ (Port 8088 / 8443)
┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│ Kong Gateway OSS (apigw)                                                                   │
│  ├── 1. basic-auth / acl       (Perimeter Authentication & Site Tenant Isolation)           │
│  ├── 2. rate-limiting          (Burst Protection, e.g. 60 req/min)                         │
│  ├── 3. post-function          (Dynamic Incident JSON & Upstream Basic Auth Injection)     │
│  └── 4. http-log plugin        (Asynchronous Telemetry & Audit Streaming)                  │
└───────────────────────┬─────────────────────────────────────────────┬───────────────────────┘
                        │ (POST Incident JSON)                        │ (Async Audit JSON)
                        ▼                                             ▼
        ┌────────────────────────────────┐            ┌───────────────────────────────────────┐
        │ iMOPS Backend                  │            │ n8n Audit Ingestion Service           │
        │ (:3000/api/incidents/monitor)  │            │ (c:\Projects\cde\n8n)                 │
        └────────────────────────────────┘            │  ├── Extracts client IP & latencies   │
                                                      │  ├── Stores in PostgreSQL             │
                                                      │  └── Appends to MinIO S3 Bronze Lake  │
                                                      └───────────────────┬───────────────────┘
                                                                          ▼
                                                      ┌───────────────────────────────────────┐
                                                      │ Analytics & Operational BI Dashboards │
                                                      └───────────────────────────────────────┘
```

---

## 3. Visual Request & Response Audit Trail

### Option 1: Streaming Audit Logs into n8n Webhook & Lakehouse (Recommended)

Kong provides an asynchronous, non-blocking **`http-log`** plugin. It captures incoming request metadata, client IP, route name, HTTP response status, and timing latencies, streaming them directly as JSON to an n8n webhook.

#### 1. Enable `http-log` Plugin on a Service:
```powershell
# Windows PowerShell
curl.exe -i -X POST http://localhost:8001/services/imops-dors-incident-service/plugins `
  -d "name=http-log" `
  -d "config.http_endpoint=http://host.docker.internal:5678/webhook/kong-audit" `
  -d "config.method=POST" `
  -d "config.timeout=5000" `
  -d "config.keepalive=60000"
```
```bash
# Linux / macOS Bash
curl -i -X POST http://localhost:8001/services/imops-dors-incident-service/plugins \
  -d "name=http-log" \
  -d "config.http_endpoint=http://host.docker.internal:5678/webhook/kong-audit" \
  -d "config.method=POST" \
  -d "config.timeout=5000" \
  -d "config.keepalive=60000"
```

#### 2. Downstream Storage Workflow (in `c:\Projects\cde\n8n`):
* n8n listens on webhook `/webhook/kong-audit`.
* Parses audit events and inserts rows into `audit_api_logs` table in PostgreSQL.
* Simultaneously archives raw event records to MinIO S3 bucket (`bronze/kong-audit/`) for compliance queries.

---

### Option 2: Capturing Full Request & Response Bodies (Payload Logging)

Standard HTTP access logs only record metadata (URLs, status codes, latencies). If audit compliance demands capturing the exact translated incident JSON and the response body from iMOPS:

Attach a Lua `post-function` plugin during the `log` phase:
```lua
-- post-function log phase
local resp = kong.service.response.get_raw_body()
local req = kong.request.get_raw_body()
kong.log.notice(string.format("[VA_AUDIT] Route=%s Status=%d ReqBody=%s RespBody=%s",
  kong.router.get_route().name,
  kong.response.get_status(),
  req or "none",
  resp or "none"
))
```

---

### Option 3: Real-Time Web-Based Log Viewer (Dozzle)

For operators who need an immediate, zero-maintenance web GUI to search, filter, and inspect real-time logs without command-line access:

Add `dozzle` to `c:\Projects\cde\apigw\docker-compose.yml`:
```yaml
dozzle:
  image: amir20/dozzle:latest
  container_name: kong-log-viewer
  volumes:
    - /var/run/docker.sock:/var/run/docker.sock
  ports:
    - "8888:8080"
  environment:
    DOZZLE_FILTER: "name=kong-gateway"
  restart: unless-stopped
```
**Access:** Open `http://localhost:8888` in any browser to get a live, searchable stream of every VA invocation, response status, and error stack.

---

## 4. Upstream Resilience, Health Checks & Circuit Breaking

When multiple camera systems send triggers simultaneously or the iMOPS backend undergoes a restart, direct IP routing can fail abruptly with cascading connection timeouts.

### Kong Upstream with Active & Passive Health Checks:

Instead of pointing the Gateway Service directly to `host.docker.internal:3000`, configure a Kong **Upstream** target:

```powershell
# 1. Create Upstream
curl.exe -i -X POST http://localhost:8001/upstreams -d "name=imops-backend-upstream"

# 2. Add Upstream Target
curl.exe -i -X POST http://localhost:8001/upstreams/imops-backend-upstream/targets `
  -d "target=host.docker.internal:3000"

# 3. Configure Active Health Check (Checks /api/health every 10 seconds)
curl.exe -i -X PATCH http://localhost:8001/upstreams/imops-backend-upstream `
  -d "healthchecks.active.healthy.interval=10" `
  -d "healthchecks.active.unhealthy.interval=5" `
  -d "healthchecks.active.http_path=/api/health"

# 4. Point Gateway Services to the Upstream
curl.exe -i -X PATCH http://localhost:8001/services/imops-dors-incident-service `
  -d "host=imops-backend-upstream" `
  -d "port=80"
```

### Circuit Breaking Benefits:
* **Self-Healing:** Kong automatically marks the upstream unhealthy if consecutive 5xx errors occur.
* **Fast Failure:** Avoids socket timeouts on camera firmware by failing fast until the backend resumes healthy status.

---

## 5. Declarative Configuration & GitOps (decK)

Currently, configurations are applied dynamically via the Kong Admin REST API (port `8001`). To ensure reproducible deployments across Development, Staging, and Production environments:

### decK Workflow:
```powershell
# 1. Dump current Kong configuration to a declarative YAML file
deck gateway dump --output-file c:\Projects\cde\apigw\kong.yaml

# 2. Validate configuration syntax and schema
deck gateway validate --state c:\Projects\cde\apigw\kong.yaml

# 3. Synchronize changes in CI/CD pipeline
deck gateway sync --state c:\Projects\cde\apigw\kong.yaml
```

### Advantages:
* **Version Control:** All services, routes, consumers, and credentials exist as declarative code in Git.
* **Pull Request Reviews:** Adding new cameras or rotating passwords follows standard code-review workflows.
* **Disaster Recovery:** A brand new Kong instance can be restored in seconds with `deck gateway sync`.

---

## 6. Security Hardening & Network Isolation

### 6.1 End-to-End TLS / HTTPS (Port 8443)
* Transition CCTV camera trigger destinations from `http://<KONG_HOST>:8088/...` to `https://<KONG_HOST>:8443/...`.
* Mount trusted SSL/TLS certificates into Kong Gateway to protect Basic Auth credentials from network sniffing.

### 6.2 IP Whitelisting / Subnet Restriction
Attach the `ip-restriction` plugin to restrict the `/va/*` endpoints so only the trusted CCTV/VA subnet can invoke triggers:
```powershell
curl.exe -i -X POST http://localhost:8001/services/imops-dors-incident-service/plugins `
  -d "name=ip-restriction" `
  -d "config.allow=192.168.10.0/24,10.100.0.0/16"
```

### 6.3 HMAC / Mutual TLS (mTLS) for Camera Appliances
For edge camera appliances that support client certificates or cryptographic signatures, transition from Basic Auth to mTLS or HMAC-SHA256 signature verification.

---

## 7. Metrics, Dashboards & Alerting

### 7.1 Prometheus Telemetry
Enable Kong's bundled `prometheus` plugin:
```powershell
curl.exe -i -X POST http://localhost:8001/plugins -d "name=prometheus"
```
Exposes standard Prometheus metrics at `http://localhost:8001/metrics`:
* `kong_http_requests_total`: Total request counter by service, route, and status code.
* `kong_latency_bucket`: Histograms for upstream latency vs gateway proxy latency.
* `kong_bandwidth_bytes`: Total ingress and egress data transfer.

### 7.2 Grafana Dashboards
* Import official Kong Grafana Dashboard (ID `7424`).
* Displays:
  - Real-time request throughput per camera route.
  - 4xx (authentication/rate-limit) and 5xx (upstream downtime) error rates.
  - 95th and 99th percentile upstream latency.

### 7.3 Automated Incident Alerts
* Configure alerting rules in Grafana or n8n to send Slack/Teams/Email notifications if:
  - Upstream latency exceeds 500ms over 3 consecutive minutes.
  - 5xx error rate exceeds 5% of total requests over a 5-minute window.
