# Kong Gateway OSS Setup (with Kong Manager UI)

This setup runs **Kong Gateway OSS 3.9** with **Kong Manager (OSS UI)** enabled, backed by a PostgreSQL 15 database using Docker Compose.

---

## Port Allocations

| Port | Service | Description | Notes |
| :--- | :--- | :--- | :--- |
| **`8088`** | Public Proxy (HTTP) | Gateway entrypoint for clients/APIs | Remapped from `8000` to avoid conflict with CompreFace (`compreface-ui`) |
| **`8443`** | Public Proxy (HTTPS) | Secure Gateway entrypoint (SSL/TLS) | Standard Kong SSL proxy port |
| **`8001`** | Admin API (HTTP) | REST API to configure Kong | Internal / administrative use |
| **`8002`** | Kong Manager UI | Web Dashboard | Access this in your browser to manage Kong |

> [!NOTE]
> **Why do I see `no Route matched with those values` at `http://localhost:8088`?**
> This is the **expected and correct behavior**. Port `8088` is the traffic gateway proxy. Until you define a **Service** and a **Route**, Kong does not know where to proxy incoming requests. 
> To configure and manage Kong visually, open **[http://localhost:8002](http://localhost:8002)**.

---

## Core Kong Concepts

| Kong Concept | Real-World Analogy | What it does | Example |
| :--- | :--- | :--- | :--- |
| **Service** | The destination / backend room | Defines the target upstream API | `https://api.open-meteo.com` |
| **Route** | The door / path to enter | The public URL path clients call | `/weather` |
| **Consumer** | **The guest / client entering the door** | Represents **WHO** is calling your API | `mobile-app`, `user-alice`, `partner-corp` |
| **Plugin** | The security guard / receptionist | Intercepts requests for auth, rate limits, transforms | `key-auth`, `rate-limiting`, `cors` |

---

## What are Consumers?

A **Consumer** in Kong represents an external client, developer, user, or application calling your APIs. 

Without Consumers, your API is completely anonymous. With Consumers, you can:

1. **Authentication (API Keys, JWT, OAuth2)**
   - Issue distinct credentials (e.g. API keys) to each consumer to identify who is making the request.
2. **Tiered Rate Limiting & Quotas**
   - Apply different speed limits per client:
     - Free Consumer: 10 requests / minute
     - Premium Consumer: 1,000 requests / minute
3. **Access Control (ACLs & Whitelisting)**
   - Authorize specific consumers to access private routes while denying others.
4. **Analytics & Tracking**
   - Monitor usage per customer or app for auditing, billing, or telemetry.

---

## Quick Start

### 1. Start the Stack

Run the following command from the `apigw` directory:

```bash
docker compose up -d
```

This starts:
1. **`kong-db`**: PostgreSQL 15 database.
2. **`kong-migrations`**: Runs one-time database bootstrap migrations and exits.
3. **`kong-gateway`**: Kong Gateway instance with Kong Manager enabled.

### 2. Verify Services

Check running containers:
```bash
docker compose ps
```

`kong-gateway` and `kong-db` should report status as `Up` (healthy), and `kong-migrations` should report `Exited (0)`.

Test the Admin API:
```bash
curl.exe -i http://localhost:8001/
```
You should receive an HTTP `200 OK` response with Kong configuration details.

### 3. Firewall Configuration (UFW) for Linux Host (`sov-webapp`)

If UFW is active on the host machine, allow Kong's proxy and management ports:

```bash
sudo bash scripts/configure_ufw_kong.sh
```

This opens:
* **Port `8088/tcp`**: HTTP Proxy (Inbound Video Analytics triggers & camera webhooks)
* **Port `8443/tcp`**: HTTPS Proxy (Secure API & webhook ingress)
* **Port `8001/tcp`**: Admin API (Required for Kong Manager UI browser calls)
* **Port `8002/tcp`**: Kong Manager Web GUI (`http://<SERVER_IP>:8002`)

---

## Accessing Kong Manager Dashboard

Open your browser and navigate to:
👉 **[http://localhost:8002](http://localhost:8002)**

The Kong Manager dashboard allows you to visually manage:
- **Gateway Services**: Upstream backends / target APIs.
- **Routes**: External paths and host rules that map client traffic to Services.
- **Consumers**: Client identities and their security credentials.
- **Plugins**: Authentication, rate-limiting, request transformers, logging, etc.

---

## Working Examples & Tutorials

### Example 1: Weather API (`wttr.in`)

#### A. Create Service & Route via Admin API:
```bash
# 1. Create the Service
curl.exe -i -X POST http://localhost:8001/services -d "name=weather-service" -d "url=https://wttr.in"

# 2. Create the Route
curl.exe -i -X POST http://localhost:8001/services/weather-service/routes -d "name=weather-route" -d "paths[]=/weather" -d "strip_path=true"
```

#### B. Test in Browser or Terminal:
- **Plain Text / ASCII weather:**
  ```bash
  curl.exe http://localhost:8088/weather/Singapore?format=3
  ```
- **Structured JSON format (`?format=j1`):**
  ```bash
  curl.exe "http://localhost:8088/weather/Singapore?format=j1"
  ```

---

### Example 2: OpenAPI REST Weather API (`Open-Meteo`)

[Open-Meteo](https://open-meteo.com) is a free OpenAPI 3.0-compliant weather service that requires no API key.

```bash
# 1. Create Service
curl.exe -i -X POST http://localhost:8001/services -d "name=open-meteo-service" -d "url=https://api.open-meteo.com"

# 2. Create Route
curl.exe -i -X POST http://localhost:8001/services/open-meteo-service/routes -d "name=open-meteo-route" -d "paths[]=/meteo" -d "strip_path=true"

# 3. Query via Kong Proxy
curl.exe "http://localhost:8088/meteo/v1/forecast?latitude=1.35&longitude=103.82&current_weather=true"
```

---

### Example 3: Protecting APIs with Consumers & API Keys (`key-auth`)

Here is how to restrict an API so only authenticated Consumers can access it:

#### 1. Enable the `key-auth` Plugin on a Route:
```bash
curl.exe -i -X POST http://localhost:8001/routes/weather-route/plugins -d "name=key-auth"
```
*(Now requests without an API key will return `HTTP 401 Unauthorized`)*

#### 2. Create a Consumer (e.g., `alice`):
```bash
curl.exe -i -X POST http://localhost:8001/consumers -d "username=alice"
```

#### 3. Issue an API Key to Alice:
```bash
curl.exe -i -X POST http://localhost:8001/consumers/alice/key-auth -d "key=alice-secret-key"
```

#### 4. Call the Route with Alice's Key:
```bash
# In the Header:
curl.exe http://localhost:8088/weather/Singapore?format=3 -H "apikey: alice-secret-key"

# Or as a Query Parameter:
curl.exe "http://localhost:8088/weather/Singapore?format=3&apikey=alice-secret-key"
```

---

## How to Configure Your Translation Flow in the UI

Once inside Kong Manager at `http://localhost:8002`:

1. **Create a Service:** 
   - Go to **Gateway Services** -> **New Service**. 
   - Enter your target destination API base URL (e.g., `https://api.targetservice.com`).
2. **Create a Route:** 
   - Under that Service, select **Routes** -> **New Route**. 
   - Set the path your client or Virtual Assistant will call (e.g., `/va-hook`) and limit methods (e.g., `GET`, `POST`).
3. **Configure Request Translation / Transformation:**
   - Under the Route or Service, navigate to **Plugins** -> **Add Plugin**.
   - Use **Request Transformer** to inject API keys, rewrite headers, or append query strings needed by the target API.
   - If you need path rewriting, adjust the route's path matching rules or use the `path` rewrite settings in the plugin.

---

## Production Video Analytics (VA) Ingress Services

Kong Gateway acts as the perimeter **Authorizer, Rate-Limiter, and Dynamic Request Translator** for physical Video Analytics edge cameras, translating camera triggers into iMOPS incident monitor payloads and forwarding them to `http://<BACKEND_HOST_IP>:13000/api/incidents/monitor`.

### Active Production Services & Routes

| Service Name | Site | Consumer | Upstream Target | Ingress Routes | Incident Type | Guide |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **`imops-sicc-incident-service`** | SICC | `va_system_consumer` (`vizzio@imops.local`) | `http://host.docker.internal:13000/api/incidents/monitor` | • `/va/sov-38alt-crowding`<br/>• `/va/sov-38alt-loitering` | • `CROWDING`<br/>• `LOITERING` | [SICC Implementation Guide](file:///c:/Projects/cde/apigw/docs/VA_SICC_Kong_Gateway_Implementation.md) |
| **`imops-dors-incident-service`** | DORS | `va_dors_consumer` (`dors_user@isems.com`) | `http://host.docker.internal:13000/api/incidents/monitor` | • `/va/dors-dop-c02-cyclist`<br/>• `/va/dors-waiting-c03-cyclist`<br/>• `/va/dors-dop-c01-illegal`<br/>• `/va/dors-dop-c02-illegal` | • `CYCLIST_GATHERING`<br/>• `ILLEGAL_PARKING` | [DORS Implementation Guide](file:///c:/Projects/cde/apigw/docs/VA_DORS_Kong_Gateway_Implementation.md) |

### Automated Setup Scripts

Automated scripts for one-click setup or rebuild are located in `apigw/scripts/`:

```bash
# SICC VA Ingress
bash scripts/setup_sicc_va.sh        # Linux (webapp)
powershell -File scripts/setup_sicc_va.ps1  # Windows

# DORS VA Ingress
bash scripts/setup_dors_va.sh        # Linux (webapp)
powershell -File scripts/setup_dors_va.ps1  # Windows
```

---

## Verifying Kong Configuration via Command Line (CLI)

Run these commands directly on the `webapp` terminal to inspect and verify Kong's live configuration:

### 1. Instant Health & Object Summary
```bash
echo "=== KONG GATEWAY STATUS ===" && \
curl -s http://localhost:8001/status | jq . && \
echo "Services:  $(curl -s http://localhost:8001/services | jq '.data | length')" && \
echo "Routes:    $(curl -s http://localhost:8001/routes | jq '.data | length')" && \
echo "Consumers: $(curl -s http://localhost:8001/consumers | jq '.data | length')" && \
echo "Plugins:   $(curl -s http://localhost:8001/plugins | jq '.data | length')"
```

### 2. Inspect Services
```bash
# Clean formatted list (Name, Target Host, Port, Path)
curl -s http://localhost:8001/services | jq -r '.data[] | "[\(.name)] -> http://\(.host):\(.port)\(.path)"'

# Full details (JSON)
curl -s http://localhost:8001/services | jq .
```

### 3. Inspect Routes & Paths
```bash
# Formatted route list with assigned paths and parent service
curl -s http://localhost:8001/routes | jq -r '.data[] | "Route: \(.name) | Paths: \(.paths | join(", ")) | Methods: \(.methods | join(","))"'
```

### 4. Inspect Consumers & Credentials
```bash
# List all consumers
curl -s http://localhost:8001/consumers | jq -r '.data[] | "Consumer: \(.username) (ID: \(.id))"'

# Check basic-auth credentials for a consumer
curl -s http://localhost:8001/consumers/va_system_consumer/basic-auth | jq .
curl -s http://localhost:8001/consumers/va_dors_consumer/basic-auth | jq .
```

### 5. Inspect Attached Plugins
```bash
# View all active plugins (rate-limiting, basic-auth, acl, post-function)
curl -s http://localhost:8001/plugins | jq -r '.data[] | "Plugin: \(.name) | Enabled: \(.enabled) | Service: \(.service.id // "none") | Route: \(.route.id // "none")"'
```

---

## Multi-Server & Remote LAN Access (e.g., Accessing WebApp from VG Appliance)

In a multi-host production environment where Kong runs on the `webapp` server (e.g., `10.65.51.251`) and operators or admins access the Kong Manager UI from a separate computer or Video Gateway (`vg`):

```
+---------------------------+                 +--------------------------------------+
|   VG Appliance / Client   |                 |          WebApp Server Linux         |
|  (Browser: 10.65.51.x)    |                 |           (10.65.51.251)             |
|                           |                 |                                      |
| Opens:                    |                 |                                      |
| http://10.65.51.251:8002 -+-- (Port 8002) ->| Kong Manager UI (Web Assets)         |
|                           |                 |                                      |
| Browser executes JS &     |                 |                                      |
| fetches live data from:   |                 |                                      |
| http://10.65.51.251:8001 -+-- (Port 8001) ->| Kong Admin API (Returns JSON Data)   |
+---------------------------+                 +--------------------------------------+
```

> [!WARNING]
> **Why does Kong Manager show 0 Services / blank tables when opened from another PC?**  
> Kong Manager is a Single-Page Application (SPA) executed **inside your browser on the client machine**.  
> If `KONG_ADMIN_GUI_API_URL` is set to `http://localhost:8001`, the client browser attempts to query `http://localhost:8001` on **itself** instead of the `webapp` server.

### How to Configure for Remote Access:
In `docker-compose.yml` on `webapp`, or via environment variables before launching:
```yaml
      KONG_ADMIN_GUI_URL: http://10.65.51.251:8002
      KONG_ADMIN_GUI_API_URL: http://10.65.51.251:8001
```
Or export them in your shell:
```bash
export KONG_ADMIN_GUI_API_URL="http://10.65.51.251:8001"
export KONG_ADMIN_GUI_URL="http://10.65.51.251:8002"
docker compose up -d
```
After restarting, reload the browser at `http://10.65.51.251:8002` and all services, routes, and plugins will render immediately.

---

## Stopping & Restarting

- **Stop containers:**
  ```bash
  docker compose down
  ```
- **Stop and wipe database data (clean reset):**
  ```bash
  docker compose down -v
  ```
- **View logs:**
  ```bash
  docker compose logs -f kong
  ```

