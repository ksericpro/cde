# Common Data Environment (CDE) - Technical Architecture & Diagram Prompts

This document contains the consolidated technical architecture, component breakdown, use cases (Taylor's University, SICC Video Analytics), observability roadmap, and detailed prompts ready for generating diagrams in ChatGPT, Mermaid.js, or Draw.io.

---

## 1. CDE Architecture & Core Components

### High-Level Components
- **API Gateway (Kong Gateway OSS 3.9)**: Secure edge ingress, rate limiting, authentication, payload transformation, and WebSocket/REST proxying.
- **Workflow & Orchestration Engine (n8n)**: Ingestion pipeline, webhook listener, scheduled watermarked pollers, and alarm dispatcher.
- **Message Broker & Fast-Path Lane (Redis Streams)**: Microsecond event buffering and pub/sub for critical alarms and immediate dispatch.
- **Data Lakehouse & Storage Tier (MinIO S3, PostgreSQL, MongoDB)**:
  - **MinIO**: Bronze (raw immutable payloads), Silver, and Gold lakehouse object storage.
  - **PostgreSQL**: Relational application data, metadata, audit trails, and Kong configuration.
  - **MongoDB**: Flexible document store for unmutated historical IoT sensor payloads.
- **Centralized Logging (ELK Stack)**: Elasticsearch, Logstash, and Kibana for log aggregation, security indexing, and root-cause analysis.
- **Infrastructure Metrics & Dashboards (Prometheus & Grafana)**: Time-series telemetry, cAdvisor/Node Exporter scraping, host health, and threshold/predictive alerting.
- **Cognitive AI & Analytics Layer (DuckDB, Python/FastAPI, AI Models)**: Automated data cleansing, enrichment, predictive maintenance, and incident triage.

### Complete Tech Stack
| Tier | Technologies | Role / Responsibility |
| :--- | :--- | :--- |
| **Edge Ingress / API Gateway** | Kong Gateway OSS 3.9 | SSL termination, API key/Basic auth, ACLs, rate limiting, WebSocket/REST proxying. |
| **ETL & Orchestration** | n8n (with Nginx SSL reverse proxy) | Inbound webhook reception, scheduled pulling, schema normalization, dual-path branching. |
| **Streaming / Cache** | Redis 7 (Redis Streams + In-memory Cache) | Urgent alarm fast-path lane, polling lock/watermarking, session state. |
| **Object Storage** | MinIO S3 Lakehouse | Raw JSON payloads, historical sensor telemetry, cold storage. |
| **Databases** | PostgreSQL 15, MongoDB 6 | State management, structured incident records, unstructured event stores. |
| **Log Management** | ELK (Elasticsearch 8, Logstash, Kibana) | Kong ingress logs, n8n pipeline logs, iMOPS application logs. |
| **Metrics & Telemetry** | Prometheus, Grafana, Node Exporter, cAdvisor | System resource monitoring (CPU, RAM, Disk I/O), Kong API latencies, HTTP error rates. |
| **Downstream Platform** | iMOPS (Facility & Incident Management) | Real-time incident response, SOP automation, command center dispatch. |
| **Visualization** | WebGL 3D Miniature Digital Twin (embedded in iMOPS) | Real-time 3D twin rendering spatial asset states via WebSockets. |

---

## 2. Taylor's University Use Case

### Workflows & Data Flows
1. **Push Ingress (Proscalar Controller -> Kong -> n8n -> iMOPS)**:
   - External door access controllers (Proscalar) push alarm events (e.g., *Door Forced Open*, *Access Denied Alert*) to Kong Gateway.
   - Kong authenticates the caller, validates schemas, and forwards payloads to the internal n8n webhook.
   - n8n categorizes severity (`critical`, `high`, `low`) and dispatches immediate incidents to the iMOPS monitoring endpoint (`/api/incidents/monitor`).
2. **Pull Polling (n8n Poller -> Proscalar Door Status every 30s -> iMOPS)**:
   - n8n runs a 30-second cron job with Redis watermarking to prevent execution overlap.
   - Polls Proscalar door status API for state updates (Locked, Unlocked, Sensor State).
   - Syncs delta changes into PostgreSQL and pushes status broadcasts to iMOPS.
3. **WebGL Miniature Digital Twin (Embedded in iMOPS)**:
   - Client browser renders a lightweight 3D miniature of Taylor's campus/building inside iMOPS.
   - Communicates bidirectionally via Kong Gateway over **REST APIs** (initial state & historical queries) and **WebSockets** (live door status updates, real-time alarm visual highlights).

---

## 3. Project SICC Use Case (SOV 38ALT Video Analytics)

### Video Analytics Ingress Architecture
1. **Edge Video Analytics (VA) Cameras & AI Engines**:
   - 21 discrete camera & analytics feeds detecting crowd gathering, loitering, unattended objects, perimeter intrusion, and unauthorized entry at SOV 38ALT.
2. **Kong Ingress & Policy Enforcement**:
   - Upstream Service: `imops-sicc-incident-service` pointing to `http://host.docker.internal:13000/api/incidents/monitor`.
   - Security: HTTP Basic Auth (`vizzio@imops.local`), ACL plugin restricted to `sicc_group`, and rate limiting set to 60 req/min.
   - Response / Request Transformation: Kong normalizes heterogeneous camera vendor schemas into standard iMOPS incident models.
3. **iMOPS Incident & SOC Response**:
   - Security operations center receives real-time alerts via Socket.IO/WebSockets with video snapshots, camera coordinates, and automated SOP action checklists.

---

## 4. Observability & Tracing Roadmap

### Telemetry & Log Routing Strategy
- **Infrastructure & API Metrics $\rightarrow$ Prometheus & Grafana**:
  - Node Exporter & cAdvisor collect Host CPU, RAM, Disk I/O, and Container health.
  - Kong Prometheus Plugin exposes API request rates, upstream latency (P50, P95, P99), and HTTP status codes (2xx/4xx/5xx).
  - Grafana renders unified dashboards for infrastructure capacity, ingress traffic, and service health.
- **Application & Gateway Logs $\rightarrow$ ELK Stack (Elasticsearch, Logstash, Kibana)**:
  - Kong Gateway access & error logs.
  - n8n workflow execution traces and failure payloads.
  - iMOPS application logs and audit records.
  - Filebeat/Logstash parses JSON fields, extracts error codes, and forwards to Elasticsearch.

### Observability Features
- **Infra Observability**:
  - Real-time CPU, RAM, Disk I/O, Network Throughput monitoring.
  - Threshold alerts (e.g., CPU > 85%, Disk Usage > 90%, Kong 5xx Error Rate > 2%).
  - Predictive alerting (Holt-Winters forecasting / linear capacity projection for disk saturation).
- **Application Tracing & APM**:
  - OpenTelemetry (OTel) / Elastic APM integration into Kong and iMOPS backend.
  - End-to-end distributed tracing across Edge Kong $\rightarrow$ n8n $\rightarrow$ iMOPS database transactions to identify processing bottlenecks.

---

## 5. Cognitive AI & Predictive Intelligence Pipeline

### Step-by-Step AI Lifecycle
```
Data Ingestion ──► Data Cleansing ──► Feature Enrichment ──► Model Evaluation ──► Workflow Action ──► Egress / Publish
 (MinIO/Postgres)    (DuckDB/Polars)       (Redis / Polars)       (ML Inference)        (n8n Engine)       (iMOPS / WebGL)
```

1. **Data Collection & Ingestion**:
   - Continuous raw ingestion into MinIO Bronze zone and PostgreSQL from IoT sensors, door controllers, and video analytics.
2. **Data Cleansing**:
   - Automated DuckDB / Polars pipeline strips noise, deduplicates entries, handles sensor dropouts, and normalizes timestamps.
3. **Data Enrichment & Feature Aggregation**:
   - Merges spatial location data, time-of-day contextual features, rolling window averages (1h, 24h, 7d), and asset age.
4. **AI/ML Model Evaluation**:
   - **Anomaly Detection**: Unsupervised Isolation Forest / Autoencoder flags unusual patterns (e.g., abnormal door access frequencies).
   - **Predictive Maintenance**: Remaining Useful Life (RUL) regression forecasting hardware failure risks before breakdown occurs.
   - **Root Cause Analysis (RCA)**: Correlation engine maps multi-source telemetry to identify incident root causes.
5. **Workflow Implementation**:
   - n8n evaluates inference confidence scores; if risk threshold is exceeded, triggers automated incident creation, technician assignment, and pre-allocated SOPs.
6. **Publish & Actionable Insights**:
   - Dispatches notifications via iMOPS command center, mobile push, and real-time visual warning indicators on the 3D WebGL Digital Twin.

---

## 6. Detailed Prompts for Drawing Diagrams in ChatGPT

Use the following detailed prompts in ChatGPT, Claude, or any LLM with diagramming capabilities (e.g., requesting Mermaid.js, PlantUML, or Draw.io XML):

---

### Prompt 1: CDE Master Architecture & Dual-Path Ingestion Diagram
```text
Act as an Enterprise Cloud Architect. Generate a comprehensive Mermaid.js architecture diagram for an enterprise Common Data Environment (CDE).

Diagram Requirements:
1. Edge & Ingress Zone:
   - External sources: Proscalar Edge Controllers (Taylor), SICC Video Analytics Cameras (SOV 38ALT), and WebGL 3D Digital Twin Client.
   - Ingress Gateway: Kong Gateway OSS 3.9 (handling SSL, Rate Limiting, Basic/Key Auth, ACLs, and Request Transformation).
2. Orchestration & Dual-Path Split:
   - Ingestion Layer: n8n Workflow Engine (receives webhooks and executes 30s scheduled pollers).
   - Bifurcation logic:
     * Path A (Urgent Alert Lane): High/Critical events route to Redis Streams for sub-second in-memory buffering -> immediate alert consumer -> iMOPS Incident API.
     * Path B (Raw Data Lakehouse): All unmodified telemetry routes asynchronously to MinIO S3 Object Storage (Bronze/Raw Bucket) -> DuckDB/Polars ETL -> PostgreSQL / MongoDB (Silver/Gold Analytical Zone).
3. Egress & Presentation Zone:
   - iMOPS Platform (Facility & Incident Management, SOP Automation).
   - WebGL 3D Miniature Digital Twin connected via Kong (REST API for queries, WebSockets for live status).
4. Observability Tier:
   - Prometheus scraping Kong Gateway, cAdvisor, and Node Exporter -> Grafana dashboards for metrics and capacity alerts.
   - ELK Stack (Logstash, Elasticsearch, Kibana) aggregating logs from Kong, n8n, and iMOPS.

Use clean subgraphs, standard styling, and clear directional labels indicating protocols (HTTPS, WSS, Redis RESP, S3 API).
```

---

### Prompt 2: Taylor's University IoT & 3D Digital Twin Sequence Diagram
```text
Act as a Solutions Architect. Generate a detailed Mermaid.js sequence diagram showing the Taylor's University IoT and Digital Twin workflow.

Participants:
- Proscalar: Proscalar Door Controller (Edge)
- Kong: Kong API Gateway (Proxy & Auth)
- n8n: n8n Orchestrator
- Redis: Redis (Lock & Fast-Path Stream)
- iMOPS: iMOPS Backend Server
- Twin: WebGL 3D Miniature Digital Twin (Browser)

Scenarios to depict in the sequence:
1. Periodic Polling (every 30s):
   - n8n checks Redis for polling lock/watermark.
   - n8n calls Proscalar Door Status API via Kong Gateway.
   - Proscalar returns 200 OK with door states (locked/open).
   - n8n writes state update to iMOPS DB and clears lock.
2. Emergency Alarm Push:
   - Door forced open event triggered at Proscalar.
   - Proscalar POSTs alert to Kong Gateway /api/v1/proscalar/alarms.
   - Kong authenticates and proxies to n8n webhook.
   - n8n identifies 'CRITICAL' severity and pushes to Redis Streams.
   - Fast-path consumer immediately notifies iMOPS incident monitor.
3. 3D Twin Real-Time Synchronization:
   - WebGL Twin connects via WebSocket (wss://) through Kong to iMOPS.
   - iMOPS broadcasts door alert via WebSocket.
   - WebGL Twin receives message and renders 3D visual alarm indicator on the corresponding door.
```

---

### Prompt 3: Project SICC (SOV 38ALT) Video Analytics Ingress Diagram
```text
Act as a Security Systems Architect. Generate a Mermaid.js flowchart showing the Video Analytics (VA) Ingress pipeline for Project SICC (SOV 38ALT).

Components and Pipeline Stages:
1. Edge Analytics Sources:
   - 21 VA camera feeds at SOV 38ALT detecting: Crowding, Loitering, Perimeter Intrusion, Unattended Objects, and Zone Violations.
2. Perimeter Gateway (Kong OSS 3.9):
   - Ingress Route: /api/v1/sicc/va-events
   - Security Plugins: HTTP Basic Auth ('vizzio@imops.local'), ACL Plugin (restricted to 'sicc_group'), Rate Limiting (60 requests/minute).
   - In-Flight Transformer: Custom Kong transformer plugin converting raw camera metadata into standard iMOPS incident payload.
3. Upstream Incident Monitoring Service:
   - Kong routes verified requests to http://host.docker.internal:13000/api/incidents/monitor.
4. Command Center & Response:
   - iMOPS dispatches real-time incident notifications over Socket.IO to SOC operators.
   - Triggers pre-configured Standard Operating Procedure (SOP) checklists and security guard dispatch.

Structure the diagram with clear component blocks, secure boundary markings, and status checks.
```

---

### Prompt 4: Comprehensive Observability & Telemetry Pipeline Diagram
```text
Act as a DevOps/SRE Architect. Generate a Mermaid.js diagram showing the centralized Observability, Metrics, and Logging pipeline for CDE.

Include two distinct pipelines:
1. Metrics & Performance Telemetry Pipeline:
   - Exporters: Node Exporter (Host CPU, Memory, Disk IOPS), cAdvisor (Docker container metrics), Kong Prometheus Plugin (latencies, 4xx/5xx error rates, throughput).
   - Scrape Engine: Prometheus Server (15s polling interval, TSDB storage, Alertmanager integration).
   - Visualization & Alerting: Grafana Dashboards displaying real-time system health, threshold alarms, and predictive capacity alerts.
2. Centralized Logging & APM Pipeline:
   - Log Producers: Kong Access/Error logs, n8n Workflow logs, iMOPS Backend logs, System syslogs.
   - Ingestion & Parsing: Logstash / Filebeat pipeline parsing JSON schemas and sanitizing tokens.
   - Indexing & Storage: Elasticsearch cluster with hot/warm index lifecycle management.
   - Analysis: Kibana dashboards for log querying, exception tracing, and root-cause analysis (RCA).

Label all data paths, ports, and monitoring protocols clearly.
```

---

### Prompt 5: Cognitive AI & Predictive Analytics Lifecycle Flowchart
```text
Act as an AI/ML Data Engineer. Generate a clean, modern Mermaid.js flowchart depicting the Cognitive AI & Predictive Intelligence lifecycle in CDE.

Lifecycle Stages to illustrate:
1. Data Ingestion & Storage:
   - Raw multi-modal telemetry from IoT sensors, door controllers, and VA feeds collected in MinIO S3 (Bronze) and PostgreSQL.
2. Data Cleansing & Preparation:
   - DuckDB & Polars batch jobs for deduplication, missing value imputation, and timestamp alignment.
3. Feature Engineering & Enrichment:
   - Extraction of rolling statistics, frequency trends, asset operational hours, and environmental telemetry.
4. Model Evaluation & Inference:
   - Anomaly Detection (Isolation Forest) evaluating sensor drift and access spikes.
   - Predictive Maintenance (RUL model) estimating equipment failure probabilities.
   - Root Cause Analysis (RCA) correlation engine.
5. Automated Workflow Triggering:
   - n8n webhook triggered when anomaly score exceeds threshold.
6. Action & Egress:
   - Automated work order creation in iMOPS.
   - Operator push notification with suggested Next-Best-Action (NBA).
   - Visual status color change rendered on WebGL 3D Miniature Digital Twin.

Use an elegant left-to-right flow with color-coded stages for Ingestion, Processing, ML Inference, and Action.
```
