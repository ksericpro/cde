# CDE Centralized Logging (ELK Stack)

This directory contains the Docker Compose stack and configuration pipelines for centralizing logs across Kong Gateway, n8n, Docker daemon containers, and host system services, as detailed in [Phase 8 of the Development Plan](file:///c:/Projects/cde/development_plan.md#phase-8-centralized-logging--log-analytics-elk-stack).

---

## 1. Objective

Provide a unified, indexed, and real-time searchable repository for all system events, API Gateway access records, errors, and container logs to accelerate debugging, incident post-mortems, and security compliance audits.

---

## 2. Architecture

```
 [ Kong Access/Error Logs (HTTP / TCP Log Plugin) ] ──┐
 [ Docker Container Logs (stdout/stderr via Filebeat) ] ──┼──► [ Logstash :5044 ] ──► [ Elasticsearch :9200 ] ──► [ Kibana :5601 ]
 [ Host System Logs (/var/log/syslog, auth.log, ufw) ] ──┘     (Filter / Grok / JSON)   (Indexed Store: cde-logs-*)  (Search, Discovery, UI)
```

- **Elasticsearch (`:9200`)**: Distributed indexing & search cluster storing structured logs partitioned by date (`cde-logs-YYYY.MM.DD`).
- **Kibana (`:5601`)**: Web query & visualization UI for searching logs, tracing request IDs, and filtering error codes.
- **Logstash (`:5044 Beats`, `:5000 TCP/JSON`)**: Pipeline engine extracting, filtering, and parsing structured fields from incoming streams.
- **Filebeat**: Lightweight container agent tailing Docker container logs (`/var/lib/docker/containers/*/*.log`) and host log files.
- **Kong TCP / HTTP Log Plugin**: Ships structured API request logs directly from Kong to Logstash.

---

## 3. Directory Layout

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

---

## 4. Quick Start

1. Start the ELK stack:
   ```bash
   docker compose up -d
   ```
2. Stream Kong Gateway access logs to Logstash:
   ```bash
   curl -X POST http://localhost:8001/plugins \
     -d "name=tcp-log" \
     -d "config.host=cde-logstash" \
     -d "config.port=5000" \
     -d "config.tls=false"
   ```
3. Open Kibana in browser:
   - URL: **http://localhost:5601**
   - Create Data View (Index Pattern): `cde-*`
   - Explore in **Discover** view.
