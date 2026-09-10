# Common Data Environment (CDE) - Phased Development & Implementation Plan

This document outlines the step-by-step implementation plan for building, testing, and operationalizing the Common Data Environment (CDE). Each phase contains specific deliverables, Docker setup instructions, configurations, and verification procedures.

---

## Roadmap Overview

```
 ┌────────────────────────────────────────────────────────────────────────┐
 │                      CDE IMPLEMENTATION PHASES                         │
 │                   Edge Ingestion to Full Observability                 │
 └────────────────────────────────────────────────────────────────────────┘
     │
     ├─► Phase 1: Ingress Edge Gateway (Kong OSS 3.9 + Kong Manager)
     │
     ├─► Phase 2: Ingestion & Orchestration Layer (n8n Webhook / Poller)
     │
     ├─► Phase 3: Fast-Path Urgent Alerting Lane (Redis Streams Broker)
     │
     ├─► Phase 4: Object Storage Lakehouse (MinIO S3 - Bronze/Raw Zone)
     │
     ├─► Phase 5: Medallion Transformation Engine (DuckDB / Polars ETL)
     │
     ├─► Phase 6: Published Data Egress & Serving API (PostgREST / FastAPI)
     │
     ├─► Phase 7: Infrastructure Monitoring & Telemetry (Prometheus & Grafana)
     │
     ├─► Phase 8: Centralized Log Aggregation & Analysis (ELK Stack)
     │
     └─► Phase 9: End-to-End Integration, Security Hardening & Acceptance Testing
```

---

## Phase 1: Ingress Edge Gateway (Kong OSS 3.9)

### Objective
Establish the secure perimeter gateway to authenticate, throttle, and route all incoming telemetry, webhooks, and outbound data queries.

### Components
- **`kong-gateway`**: Kong OSS 3.9 listening on port `8088` (HTTP proxy) and `8443` (HTTPS proxy).
- **`kong-db`**: PostgreSQL 15 for declarative/persisted gateway state.
- **`kong-manager`**: Visual UI dashboard on port `8002`.

### Setup Instructions
1. Navigate to the `apigw` directory:
   ```bash
   cd c:\Projects\cde\apigw
   ```
2. Start the gateway stack:
   ```bash
   docker compose up -d
   ```
3. Verify running containers:
   ```bash
   docker compose ps
   ```

### Verification & Testing
- Query the Kong Admin API:
  ```bash
  curl.exe -i http://localhost:8001/
  ```
  *Expected:* HTTP `200 OK` with Kong engine version `3.9.0`.
- Open Kong Manager UI in browser: **[http://localhost:8002](http://localhost:8002)**.

---

## Phase 2: Ingestion & Orchestration Engine (n8n)

### Objective
Deploy the workflow engine responsible for receiving pushed webhooks from Kong and scheduling pull tasks for external third-party vendor APIs.

### Components
- **`cde-n8n`**: Official n8n container on port `5678` with persistent storage in `./n8n_data`.

### Setup Instructions
1. Navigate to the `n8n` directory:
   ```bash
   cd c:\Projects\cde\n8n
   ```
2. Launch the n8n container:
   ```bash
   docker compose up -d
   ```
3. Access the visual editor at **[http://localhost:5678](http://localhost:5678)** and create the primary admin credentials.

### Gateway Integration
Register n8n inside Kong to proxy inbound requests:
```bash
# 1. Register n8n upstream service
curl.exe -i -X POST http://localhost:8001/services \
  -d "name=n8n-service" \
  -d "url=http://host.docker.internal:5678"

# 2. Expose the telemetry route
curl.exe -i -X POST http://localhost:8001/services/n8n-service/routes \
  -d "name=telemetry-route" \
  -d "paths[]=/api/v1/telemetry" \
  -d "strip_path=false"
```

### Verification & Testing
1. In n8n, create a new workflow with a **Webhook Node** listening on `POST /webhook/telemetry`.
2. Post a payload to Kong Gateway:
   ```bash
   curl.exe -i -X POST http://localhost:8088/api/v1/telemetry \
     -H "Content-Type: application/json" \
     -d "{\"event_id\":\"evt-001\",\"severity\":\"INFO\",\"reading\":23.4}"
   ```
3. Confirm the execution appears in the n8n execution log.

---

## Phase 3: Fast-Path Urgent Alert Lane (Redis Streams)

### Objective
Implement sub-5ms message queuing for high-priority incidents (`CRITICAL`, `ALARM`) that bypass database writes and trigger real-time actions.

### Components
- **Redis Server**: Redis 7+ instance (using `imops-redis` on port `6379` or dedicated service).
- **Redis Stream Topic**: `stream:urgent`.
- **Alert Dispatcher**: n8n workflow or consumer script listening to consumer group `alerts-group`.

### Setup Instructions
1. Ensure Redis is accessible:
   ```bash
   docker exec -it imops-redis redis-cli ping
   # Expected: PONG
   ```
2. Create the consumer group in Redis:
   ```bash
   docker exec -it imops-redis redis-cli XGROUP CREATE stream:urgent alerts-group $ MKSTREAM
   ```

### Workflow Configuration (Inside n8n)
1. Add an **If / Switch Node** after the webhook trigger:
   - Condition: `{{ $json.body.severity }} in ["CRITICAL", "ALARM", "HIGH"]`
2. Connect the **True** branch to a **Redis Node**:
   - **Operation:** Execute Command
   - **Command:**
     ```
     XADD stream:urgent * event_id {{ $json.body.event_id }} severity {{ $json.body.severity }} message {{ $json.body.message }}
     ```
3. Create an **Alert Consumer Workflow** in n8n (or standalone Python worker):
   - Trigger: Cron / continuous loop reading `XREADGROUP GROUP alerts-group worker-1 STREAMS stream:urgent >`
   - Actions: Send Slack message, trigger SMS, or call downstream incident webhook.

### Verification & Testing
Publish an urgent payload:
```bash
curl.exe -i -X POST http://localhost:8088/api/v1/telemetry \
  -H "Content-Type: application/json" \
  -d "{\"event_id\":\"evt-999\",\"severity\":\"CRITICAL\",\"message\":\"High pressure breach\"}"
```
Verify the item in Redis:
```bash
docker exec -it imops-redis redis-cli XREVRANGE stream:urgent + - COUNT 1
```

---

## Phase 4: Lakehouse Object Storage (MinIO - Bronze/Raw Zone)

### Objective
Deploy an S3-compatible object store (MinIO) to capture full, unmutated JSON payloads with lifecycle expiration policies.

### Components
- **`cde-minio`**: MinIO Server on port `9000` (S3 API) and `9001` (Web Console).
- **Buckets**:
  - `s3://lake-raw/` (Bronze)
  - `s3://lake-curated/` (Silver)
  - `s3://lake-publish/` (Gold)

### Setup Instructions
Add the MinIO definition to the CDE stack (or create `c:\Projects\cde\minio\docker-compose.yml`):
```yaml
services:
  minio:
    image: minio/minio:latest
    container_name: cde-minio
    restart: unless-stopped
    command: server /data --console-address ":9001"
    environment:
      MINIO_ROOT_USER: cdeadmin
      MINIO_ROOT_PASSWORD: cdepassword123
    ports:
      - "9000:9000"
      - "9001:9001"
    volumes:
      - minio_data:/data
    networks:
      - cde-network

volumes:
  minio_data:
```

Launch MinIO and initialize buckets:
```bash
docker compose up -d
# Create buckets via MinIO Client (mc)
docker run --rm --network cde-network minio/mc alias set local http://cde-minio:9000 cdeadmin cdepassword123
docker run --rm --network cde-network minio/mc mb local/lake-raw local/lake-curated local/lake-publish
```

### Ingestion Integration
In n8n, connect **Path B (All Payloads)** to an **S3 / HTTP Node**:
- Target: `http://cde-minio:9000/lake-raw/{{ $now.format('yyyy/MM/dd') }}/{{ $json.event_id }}.json`

### Verification & Testing
Inspect the bucket via browser at **[http://localhost:9001](http://localhost:9001)** or query:
```bash
docker run --rm --network cde-network minio/mc ls local/lake-raw/
```

---

## Phase 5: Medallion Transformation Engine (DuckDB / Polars ETL)

### Objective
Transform raw JSON payloads into clean, schema-enforced, partitioned Parquet files (Silver) and rollup daily analytics (Gold).

### Components
- **DuckDB Container / Script**: Executes S3-direct SQL transformations.
- **Scheduler**: n8n Cron Trigger or cron daemon running every 5–15 minutes.

### Step-by-Step Transformations
#### Step 1: Raw $\rightarrow$ Curated (Bronze to Silver)
DuckDB SQL script (`etl_curated.sql`):
```sql
INSTALL httpfs; LOAD httpfs;
SET s3_endpoint='host.docker.internal:9000';
SET s3_access_key_id='cdeadmin';
SET s3_secret_access_key='cdepassword123';
SET s3_use_ssl=false;
SET s3_url_style='path';

COPY (
  SELECT 
    event_id::VARCHAR AS event_id,
    strptime(timestamp, '%Y-%m-%dT%H:%M:%SZ') AS event_timestamp,
    severity::VARCHAR AS severity,
    reading::DOUBLE AS reading,
    source::VARCHAR AS source,
    current_timestamp AS ingested_at
  FROM read_json_auto('s3://lake-raw/**/*.json')
  WHERE event_id IS NOT NULL
) TO 's3://lake-curated/telemetry/' (FORMAT PARQUET, PARTITION_BY (severity), OVERWRITE_OR_IGNORE 1);
```

#### Step 2: Curated $\rightarrow$ Publish (Silver to Gold)
DuckDB SQL script (`etl_publish.sql`):
```sql
COPY (
  SELECT 
    date_trunc('day', event_timestamp) AS date,
    source,
    severity,
    count(*) AS total_events,
    avg(reading) AS avg_reading,
    max(reading) AS max_reading
  FROM read_parquet('s3://lake-curated/telemetry/**/*.parquet')
  GROUP BY 1, 2, 3
) TO 's3://lake-publish/daily_summary/' (FORMAT PARQUET, OVERWRITE_OR_IGNORE 1);
```

### Verification & Testing
Execute test queries directly against MinIO via DuckDB CLI:
```bash
duckdb -c "INSTALL httpfs; LOAD httpfs; SELECT * FROM read_parquet('s3://lake-publish/daily_summary/**/*.parquet') LIMIT 5;"
```

---

## Phase 6: Published Data Egress & Serving API

### Objective
Provide low-latency ($<20\text{ ms}$) query endpoints for Virtual Assistants, Dashboards, and external consumers, secured behind Kong.

### Components
- **PostgreSQL Operational DB**: Holds mirrored Gold aggregates.
- **Serving Microservice (PostgREST / FastAPI)**: Translates REST calls into SQL queries.
- **Kong Egress Route**: Enforces API keys and caches responses (`proxy-cache`).

### Setup Instructions
1. Create a lightweight FastAPI serving container (`serving-api`):
   ```python
   from fastapi import FastAPI
   import duckdb

   app = FastAPI(title="CDE Published Data API")

   @app.get("/api/v1/metrics/daily")
   def get_daily_metrics():
       con = duckdb.connect()
       con.execute("INSTALL httpfs; LOAD httpfs; ...")
       df = con.execute("SELECT * FROM read_parquet('s3://lake-publish/daily_summary/**/*.parquet')").df()
       return df.to_dict(orient="records")
   ```
2. Register the service in Kong Gateway:
   ```bash
   # Service definition
   curl.exe -i -X POST http://localhost:8001/services \
     -d "name=cde-publish-service" \
     -d "url=http://host.docker.internal:8000"

   # Route definition
   curl.exe -i -X POST http://localhost:8001/services/cde-publish-service/routes \
     -d "name=publish-route" \
     -d "paths[]=/api/v1/metrics"

   # Enable Proxy Caching (10-minute TTL)
   curl.exe -i -X POST http://localhost:8001/routes/publish-route/plugins \
     -d "name=proxy-cache" \
     -d "config.response_code[]=200" \
     -d "config.content_type[]=application/json" \
     -d "config.cache_ttl=600"
   ```

### Verification & Testing
1. Call the endpoint through Kong:
   ```bash
   curl.exe -i http://localhost:8088/api/v1/metrics/daily
   ```
2. Check headers: The first request returns `X-Cache-Status: Miss`; subsequent requests return `X-Cache-Status: Hit` in $< 2\text{ ms}$.

---

## Phase 7: Infrastructure Monitoring & Telemetry (Prometheus & Grafana)

### Objective
Establish continuous, real-time metrics collection and visual dashboards for all CDE hardware infrastructure, Docker containers, and API Gateway traffic. Provide automated health alerts for CPU/RAM exhaustion, disk saturation, gateway latency spikes, and downstream service failures.

### Observability Architecture
```
 [ Host Metrics (Node Exporter :9100) ] ──────────┐
 [ Container Metrics (cAdvisor :8080) ] ──────────┼──► [ Prometheus Server :9090 ] ──► [ Grafana Dashboards :3000 ]
 [ Kong Gateway (Prometheus Plugin :8001/metrics) ]──┤        (Scrapes every 15s)         (Visuals & Alert Rules)
 [ Redis / MinIO / n8n Telemetry Endpoints ] ───────┘
```

### Components
- **`cde-prometheus`**: Time-series database scraping metrics targets on a 15-second interval (port `9090`).
- **`cde-grafana`**: Visualization engine with pre-provisioned data sources and dashboards (port `3000`).
- **`cde-node-exporter`**: Host-level collector measuring system CPU, RAM, disk I/O, swap, and network throughput (port `9100`).
- **`cde-cadvisor`**: Google cAdvisor measuring per-container resource consumption, restart counts, and throttling (port `8080`).
- **`kong-prometheus`**: Kong built-in plugin exposing request counts, latencies, HTTP status codes (`2xx`/`4xx`/`5xx`), and upstream health via `http://localhost:8001/metrics`.

### Setup Instructions
1. Directory structure under `c:\Projects\cde\grafana`:
   ```
   grafana/
   ├── docker-compose.yml
   ├── prometheus/
   │   └── prometheus.yml
   └── provisioning/
       ├── datasources/
       │   └── prometheus-datasource.yml
       └── dashboards/
           ├── dashboards.yml
           └── definitions/
               ├── host_node_overview.json
               ├── docker_cadvisor_overview.json
               └── kong_gateway_overview.json
   ```
2. Docker Compose configuration (`grafana/docker-compose.yml`):
   ```yaml
   services:
     prometheus:
       image: prom/prometheus:v2.53.0
       container_name: cde-prometheus
       restart: unless-stopped
       ports:
         - "9090:9090"
       volumes:
         - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
         - prometheus_data:/prometheus
       command:
         - '--config.file=/etc/prometheus/prometheus.yml'
         - '--storage.tsdb.path=/prometheus'
         - '--storage.tsdb.retention.time=15d'
         - '--web.enable-lifecycle'
       networks:
         - cde-network

     grafana:
       image: grafana/grafana:11.1.0
       container_name: cde-grafana
       restart: unless-stopped
       ports:
         - "3000:3000"
       environment:
         - GF_SECURITY_ADMIN_USER=admin
         - GF_SECURITY_ADMIN_PASSWORD=cdepassword123
         - GF_USERS_ALLOW_SIGN_UP=false
       volumes:
         - grafana_data:/var/lib/grafana
         - ./provisioning:/etc/grafana/provisioning:ro
       networks:
         - cde-network
       depends_on:
         - prometheus

     node-exporter:
       image: prom/node-exporter:v1.8.1
       container_name: cde-node-exporter
       restart: unless-stopped
       ports:
         - "9100:9100"
       volumes:
         - /proc:/host/proc:ro
         - /sys:/host/sys:ro
         - /:/rootfs:ro
       command:
         - '--path.procfs=/host/proc'
         - '--path.rootfs=/rootfs'
         - '--path.sysfs=/host/sys'
         - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'
       networks:
         - cde-network

     cadvisor:
       image: gcr.io/cadvisor/cadvisor:v0.49.1
       container_name: cde-cadvisor
       restart: unless-stopped
       ports:
         - "8080:8080"
       volumes:
         - /:/rootfs:ro
         - /var/run:/var/run:ro
         - /sys:/sys:ro
         - /var/lib/docker/:/var/lib/docker:ro
         - /dev/disk/:/dev/disk:ro
       devices:
         - /dev/kmsg
       privileged: true
       networks:
         - cde-network

   volumes:
     prometheus_data:
     grafana_data:

   networks:
     cde-network:
       external: true
   ```
3. Prometheus scraping configuration (`grafana/prometheus/prometheus.yml`):
   ```yaml
   global:
     scrape_interval: 15s
     evaluation_interval: 15s

   scrape_configs:
     - job_name: 'prometheus'
       static_configs:
         - targets: ['localhost:9090']

     - job_name: 'node-exporter'
       static_configs:
         - targets: ['cde-node-exporter:9100']

     - job_name: 'cadvisor'
       static_configs:
         - targets: ['cde-cadvisor:8080']

     - job_name: 'kong-gateway'
       metrics_path: /metrics
       static_configs:
         - targets: ['kong-gateway:8001']
   ```
4. Enable Kong Prometheus Plugin:
   ```bash
   # Enable prometheus metrics collection globally on Kong Gateway
   curl.exe -i -X POST http://localhost:8001/plugins \
     -d "name=prometheus" \
     -d "config.status_code_metrics=true" \
     -d "config.latency_metrics=true" \
     -d "config.bandwidth_metrics=true" \
     -d "config.upstream_health_metrics=true"
   ```

### Verification & Testing
1. Verify Kong metrics scraping endpoint:
   ```bash
   curl.exe -i http://localhost:8001/metrics
   ```
   *Expected:* Output containing `kong_http_requests_total`, `kong_latency_bucket`, and `kong_upstream_target_health`.
2. Verify Prometheus targets health:
   - Browse to `http://localhost:9090/targets`.
   - Confirm all endpoints (`node-exporter`, `cadvisor`, `kong-gateway`) show **UP**.
3. Access Grafana at **[http://localhost:3000](http://localhost:3000)** (User: `admin` / Password: `cdepassword123`).
4. Validate dashboards:
   - **Host Performance:** CPU usage, memory consumption, available disk space on root volume.
   - **Container Performance:** CPU/RAM per container (`kong-gateway`, `cde-n8n`, `kong-db`).
   - **Gateway Performance:** Total traffic throughput, P95 latency distribution, 4xx/5xx error rates.

---

## Phase 8: Centralized Logging & Log Analytics (ELK Stack)

### Objective
Unify and centralize log streams across all CDE components (Kong Gateway access/error logs, n8n workflow execution logs, Docker daemon container streams, and host security/UFW logs) into an indexed, searchable Elasticsearch repository with Kibana visualizations and saved search queries.

### Logging Architecture
```
 [ Kong Access/Error Logs (HTTP / TCP Log Plugin) ] ──┐
 [ Docker Container Logs (stdout/stderr via Filebeat) ] ──┼──► [ Logstash :5044 ] ──► [ Elasticsearch :9200 ] ──► [ Kibana :5601 ]
 [ Host System Logs (/var/log/syslog, auth.log, ufw) ] ──┘     (Filter / Grok / JSON)   (Indexed Store: cde-logs-*)  (Search, Discovery, UI)
```

### Components
- **`cde-elasticsearch`**: Distributed search and storage engine storing parsed log events in time-partitioned daily indices `cde-logs-YYYY.MM.DD` (port `9200`). Configured for single-node development/edge deployment with bounded JVM heaps.
- **`cde-kibana`**: Log analytics and visual query UI (port `5601`) for real-time log tailing, search filters, and security incident investigation.
- **`cde-logstash`**: Pipeline engine accepting Beats log data (port `5044`), applying Grok pattern extraction to parse unformatted lines, and standardizing JSON schemas before outputting to Elasticsearch.
- **`cde-filebeat`**: Lightweight agent mounted to host Docker container logs (`/var/lib/docker/containers/*/*.log`) and host log files (`/var/log/syslog`, `/var/log/ufw.log`) with automated container metadata enrichment.
- **`kong-tcp-log` / `kong-http-log`**: Kong plugins streaming structured gateway telemetry (request headers, response status, client IP, route/service IDs, upstream latencies) directly into Logstash/Elasticsearch.

### Setup Instructions
1. Directory structure under `c:\Projects\cde\elk`:
   ```
   elk/
   ├── docker-compose.yml
   ├── logstash/
   │   ├── config/
   │   │   └── logstash.yml
   │   └── pipeline/
   │       └── logstash.conf
   └── filebeat/
       └── filebeat.yml
   ```
2. Docker Compose configuration (`elk/docker-compose.yml`):
   ```yaml
   services:
     elasticsearch:
       image: docker.elastic.co/elasticsearch/elasticsearch:8.14.3
       container_name: cde-elasticsearch
       restart: unless-stopped
       environment:
         - node.name=cde-es01
         - cluster.name=cde-docker-cluster
         - discovery.type=single-node
         - bootstrap.memory_lock=true
         - "ES_JAVA_OPTS=-Xms1g -Xmx1g"
         - xpack.security.enabled=false
       ulimits:
         memlock:
           soft: -1
           hard: -1
         nofile:
           soft: 65536
           hard: 65536
       volumes:
         - es_data:/usr/share/elasticsearch/data
       ports:
         - "9200:9200"
       networks:
         - cde-network

     logstash:
       image: docker.elastic.co/logstash/logstash:8.14.3
       container_name: cde-logstash
       restart: unless-stopped
       volumes:
         - ./logstash/pipeline/logstash.conf:/usr/share/logstash/pipeline/logstash.conf:ro
       environment:
         - "LS_JAVA_OPTS=-Xms512m -Xmx512m"
       ports:
         - "5044:5044"
         - "5000/tcp:5000/tcp"
       networks:
         - cde-network
       depends_on:
         - elasticsearch

     kibana:
       image: docker.elastic.co/kibana/kibana:8.14.3
       container_name: cde-kibana
       restart: unless-stopped
       ports:
         - "5601:5601"
       environment:
         - ELASTICSEARCH_HOSTS=http://elasticsearch:9200
       networks:
         - cde-network
       depends_on:
         - elasticsearch

     filebeat:
       image: docker.elastic.co/beats/filebeat:8.14.3
       container_name: cde-filebeat
       user: root
       restart: unless-stopped
       volumes:
         - ./filebeat/filebeat.yml:/usr/share/filebeat/filebeat.yml:ro
         - /var/lib/docker/containers:/var/lib/docker/containers:ro
         - /var/run/docker.sock:/var/run/docker.sock:ro
         - /var/log:/var/log:ro
       networks:
         - cde-network
       depends_on:
         - logstash

   volumes:
     es_data:

   networks:
     cde-network:
       external: true
   ```
3. Logstash pipeline configuration (`elk/logstash/pipeline/logstash.conf`):
   ```ruby
   input {
     beats {
       port => 5044
     }
     tcp {
       port => 5000
       codec => json_lines
     }
   }

   filter {
     if [fields][service] == "kong" {
       mutate {
         add_field => { "[@metadata][target_index]" => "cde-kong-logs" }
       }
     } else if [docker][container][name] =~ "n8n" {
       mutate {
         add_field => { "[@metadata][target_index]" => "cde-n8n-logs" }
       }
     } else {
       mutate {
         add_field => { "[@metadata][target_index]" => "cde-system-logs" }
       }
     }
   }

   output {
     elasticsearch {
       hosts => ["http://elasticsearch:9200"]
       index => "%{[@metadata][target_index]}-%{+YYYY.MM.dd}"
     }
   }
   ```
4. Configure Kong Gateway Log Shipping:
   ```bash
   # Enable Kong TCP Log plugin shipping structured access logs to Logstash:5000
   curl.exe -i -X POST http://localhost:8001/plugins \
     -d "name=tcp-log" \
     -d "config.host=cde-logstash" \
     -d "config.port=5000" \
     -d "config.tls=false"
   ```

### Verification & Testing
1. Check Elasticsearch node status:
   ```bash
   curl.exe -i http://localhost:9200/_cluster/health?pretty
   ```
   *Expected:* Cluster status `"green"` or `"yellow"` (single node).
2. Access Kibana at **[http://localhost:5601](http://localhost:5601)**:
   - Navigate to **Stack Management** $\rightarrow$ **Data Views** (Index Patterns).
   - Create index pattern `cde-*` matching timestamp field `@timestamp`.
3. Generate Gateway traffic:
   ```bash
   curl.exe -i http://localhost:8088/va/sov-38alt-crowding -u "vizzio@imops.local:xAJHkkm7m3V5MhtF0xGM"
   ```
4. Verify in **Kibana Discover**:
   - Filter by `service: kong` or `response.status: 200`.
   - Confirm request trace includes client IP, latency, URI, and credential identity.

---

## Phase 9: End-to-End Integration, Security Hardening & Acceptance Testing

### Objective
Validate end-to-end telemetry flow from edge ingress through to lake storage, transformation, serving, real-time metrics monitoring, and centralized logging, while enforcing production firewall and credential security policies.

### Deliverables & Checklist
- [ ] **End-to-End Ingestion Validation:** Pushing a mock sensor batch triggers both the urgent alert (Redis) and persists to MinIO raw.
- [ ] **Automated Lakehouse ETL:** Scheduled DuckDB job runs without manual intervention and updates Gold Parquet.
- [ ] **Egress Performance:** Virtual Assistant queries `/api/v1/metrics` and receives responses in $< 20\text{ ms}$.
- [ ] **Infrastructure Observability (Grafana):**
  - Host CPU/RAM/Disk and container health dashboards operational at `http://localhost:3000`.
  - Kong Prometheus metrics actively plotting request rates, error codes, and upstream latencies.
- [ ] **Centralized Logging (ELK):**
  - Kong gateway access logs automatically streamed to Elasticsearch via Logstash/Filebeat.
  - All Docker container stdout/stderr searchable in Kibana Discover (`http://localhost:5601`).
- [ ] **Security Hardening:**
  - `key-auth` or basic authentication enabled on all public routes.
  - Rate limiting enforced (e.g., 60-100 requests/minute per consumer).
  - Kong Admin API (`:8001`) and Kong Manager (`:8002`) protected behind host firewall (UFW) or basic auth.
  - Elasticsearch and Grafana secured with non-default administrative credentials.
  - CORS headers restricted to permitted dashboard origins.

---

## Implementation Progress Tracker

| Phase | Description | Status | Target Date | Notes |
| :--- | :--- | :--- | :--- | :--- |
| **Phase 1** | Kong Gateway OSS 3.9 Setup | **Completed** | Day 1 | Running on `:8088`, `:8001`, `:8002` |
| **Phase 2** | n8n Orchestrator Deployment | **Completed** | Day 1 | Running on `:5678`, connected to `cde-network` |
| **Phase 3** | Fast-Path Alert Lane (Redis Streams) | **Ready to Build** | Day 2 | Redis available on `:6379` |
| **Phase 4** | MinIO Object Store (Bronze Zone) | **Pending** | Day 3 | Buckets: `raw`, `curated`, `publish` |
| **Phase 5** | DuckDB/Polars Lakehouse ETL | **Pending** | Day 4 | SQL transformation scripts |
| **Phase 6** | Egress API & Kong Caching | **Pending** | Day 5 | PostgREST / FastAPI serving |
| **Phase 7** | Infrastructure Monitoring (Grafana + Prometheus) | **Pending** | Day 6 | Host, cAdvisor & Kong Gateway dashboards |
| **Phase 8** | Centralized Logging (ELK Stack) | **Pending** | Day 7 | Elasticsearch, Logstash, Kibana & Filebeat |
| **Phase 9** | Hardening & E2E Acceptance Testing | **Pending** | Day 8 | Final acceptance, security & audit |
