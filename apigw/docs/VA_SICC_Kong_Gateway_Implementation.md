# Kong Gateway - Video Analytics (VA) Ingress Implementation Guide

This guide details the end-to-end architecture and configuration steps for using **Kong Gateway OSS 3.9** as the **Translator, Authorizer, and Throttler**, forwarding directly to the iMOPS Incident Monitor API at:
`http://<BACKEND_HOST_IP>:13000/api/incidents/monitor` *(Host port 13000 maps to container port 3000)*.

### Direct Backend Specification:
```http
POST http://<BACKEND_HOST_IP>:13000/api/incidents/monitor
Authorization: Basic <Base64(username:password)>
Content-Type: application/json
```

> [!NOTE]
> **No Bearer Token Needed:** iMOPS `/api/incidents/monitor` accepts HTTP Basic Authentication directly. Kong authorizes the camera at the perimeter, preserves the `Authorization: Basic ...` header, injects `Content-Type: application/json`, and attaches the dynamic incident payload with a live Unix timestamp.

Both **Windows (PowerShell)** and **Linux / macOS (Bash)** commands are provided for every step.

---

## 1. Overview & Architecture

### Kong's Role as the Gateway
1. **Perimeter Authorizer:** Checks incoming credentials (`username:password`) via the `basic-auth` plugin.
2. **Pass-Through Authentication:** Forwards `Authorization: Basic <Base64(username:password)>` to iMOPS so the backend attributes the incident to the user.
3. **Dynamic Request Translator:** Converts camera triggers (`GET` or `POST`) into `POST`, sets `Content-Type: application/json`, and attaches the exact JSON incident payload with a live Unix timestamp (`os.time()`).
4. **Throttler & Rate Limiter:** Protects iMOPS from alert flooding (e.g. max 60 requests/minute).
5. **Zero iMOPS Code Changes:** When new VAs or cameras come along, you only add new Routes in Kong on the fly.

### Target Virtual Assistants (VAs)
The gateway provides dynamic translation for all 21 production Video Analytics (VA) cameras at **SOV 38ALT**:

| # | Public Ingress Route Path | Incident Type | Camera / Sensor | Webhook Identifier |
|---|---|---|---|---|
| **1** | `GET/POST /va/sov-38alt-l4-icc-1-crowding` | `CROWDING` | SOV 38ALT L4 ICC 1 | `crowding_sov_38alt_l4_icc_1` |
| **2** | `GET/POST /va/sov-38alt-l4-lift-lobby-loitering` | `LOITERING` | SOV 38ALT L4 Lift Lobby | `loitering_sov_38alt_l4_lift_lobby` |
| **3** | `GET/POST /va/sov-38alt-main-gate-smoking` | `SMOKING` | SOV 38ALT Main Gate | `smoking_sov_38alt_main_gate` |
| **4** | `GET/POST /va/sov-38alt-main-gate-fire` | `FIRE` | SOV 38ALT Main Gate | `fire_sov_38alt_main_gate` |
| **5** | `GET/POST /va/sov-38alt-carpark-lot-1-illegal-parking` | `ILLEGAL_PARKING` | SOV 38ALT Carpark Lot 1 | `illegal_parking_sov_38alt_carpark_lot_1` |
| **6** | `GET/POST /va/sov-38alt-l1-lift-lobby-loitering` | `LOITERING` | SOV 38ALT L1 Lift Lobby | `loitering_sov_38alt_l1_lift_lobby` |
| **7** | `GET/POST /va/sov-38alt-l4-corridor-o-s-war-room-loitering` | `LOITERING` | SOV 38ALT L4 Corridor o/s War Room | `loitering_sov_38alt_l4_corridor_o_s_war_room` |
| **8** | `GET/POST /va/sov-38alt-l4-interlock-loitering` | `LOITERING` | SOV 38ALT L4 Interlock | `loitering_sov_38alt_l4_interlock` |
| **9** | `GET/POST /va/sov-38alt-l5-corridor-loitering` | `LOITERING` | SOV 38ALT L5 Corridor | `loitering_sov_38alt_l5_corridor` |
| **10** | `GET/POST /va/sov-38alt-side-fencing-intrusion` | `INTRUSION` | SOV 38ALT Side Fencing | `intrusion_sov_38alt_side_fencing` |
| **11** | `GET/POST /va/sov-38alt-side-fencing-smoking` | `SMOKING` | SOV 38ALT Side Fencing | `smoking_sov_38alt_side_fencing` |
| **12** | `GET/POST /va/sov-38alt-side-fencing-fire` | `FIRE` | SOV 38ALT Side Fencing | `fire_sov_38alt_side_fencing` |
| **13** | `GET/POST /va/sov-38alt-roof-top-loitering` | `LOITERING` | SOV 38ALT Roof Top | `loitering_sov_38alt_roof_top` |
| **14** | `GET/POST /va/sov-38alt-l2-lift-lobby-loitering` | `LOITERING` | SOV 38ALT L2 Lift Lobby | `loitering_sov_38alt_l2_lift_lobby` |
| **15** | `GET/POST /va/sov-38alt-l3-lift-lobby-loitering` | `LOITERING` | SOV 38ALT L3 Lift Lobby | `loitering_sov_38alt_l3_lift_lobby` |
| **16** | `GET/POST /va/sov-38alt-l2-main-lobby-loitering` | `LOITERING` | SOV 38ALT L2 Main Lobby | `loitering_sov_38alt_l2_main_lobby` |
| **17** | `GET/POST /va/sov-38alt-l2-reception-loitering` | `LOITERING` | SOV 38ALT L2 Reception | `loitering_sov_38alt_l2_reception` |
| **18** | `GET/POST /va/sov-38alt-main-road-loitering` | `LOITERING` | SOV 38ALT Main Road | `loitering_sov_38alt_main_road` |
| **19** | `GET/POST /va/sov-38alt-l6-lift-lobby-loitering` | `LOITERING` | SOV 38ALT L6 Lift Lobby | `loitering_sov_38alt_l6_lift_lobby` |
| **20** | `GET/POST /va/sov-38alt-l5-o-s-cyber-room-loitering` | `LOITERING` | SOV 38ALT L5 o/s Cyber Room | `loitering_sov_38alt_l5_o_s_cyber_room` |
| **21** | `GET/POST /va/sov-38alt-main-gate-perimeter-intrusion` | `INTRUSION` | SOV 38ALT Main Gate Perimeter | `intrusion_sov_38alt_main_gate_perimeter` |

---

## 2. Architecture & Request Flow

```mermaid
sequenceDiagram
    autonumber
    participant VA as VA Camera / Engine
    participant Kong as Kong Gateway (Port 8088/8443)
    participant Monitor as iMOPS Monitor (http://<BACKEND_HOST_IP>:13000/api/incidents/monitor)

    VA->>Kong: GET or POST /va/sov-38alt-l4-icc-1-crowding (Basic Auth)
    Note over Kong: 1. Authorize camera (Basic Auth)<br/>2. Apply Rate Limit (60 req/min)<br/>3. Mutate method to POST<br/>4. Preserve Authorization: Basic <base64><br/>5. Inject Content-Type: application/json<br/>6. Inject Live Timestamp & Incident JSON
    Kong->>Monitor: POST /api/incidents/monitor (Basic Auth + JSON Body)
    Monitor-->>Kong: HTTP 200 OK (Incident Created & Broadcast)
    Kong-->>VA: HTTP 200 OK
```

---

## 3. Kong Core Concepts & Terminology

| Kong Concept | Real-World Analogy | Meaning & Definition | Role in this Project |
| :--- | :--- | :--- | :--- |
| **Gateway Service** | **The Destination / Upstream API** | Represents the backend API endpoint where traffic is delivered. | `http://host.docker.internal:13000/api/incidents/monitor` |
| **Route** | **The Public Door / Exposed API** | The public URL path exposed on Kong. Cameras call this on port `8088`/`8443`. | `/va/sov-38alt-crowding` and `/va/sov-38alt-loitering` |
| **Consumer** | **The Client Identity** | Represents WHO is calling the gateway. Credentials belong to Consumers. | `va_system_consumer` (credentials: `vizzio@imops.local`) |
| **Plugin** | **The Security & Policy Interceptor** | Middleware attached to Services or Routes. | • `basic-auth`: Authorizer<br/>• `rate-limiting`: Throttler<br/>• `pre-function`: Translator |

---

## 4. Transformation & Mapping Rules

Kong dynamically transforms incoming camera triggers into the full iMOPS incident monitor schema:

### 4.1 Protocol & Header Transformation Rules

| Inbound Trigger (From Camera) | Outbound Request (To iMOPS API) | Transformation Rule / Reason |
| :--- | :--- | :--- |
| **HTTP Method:** `GET` or `POST` | **HTTP Method:** `POST` | iMOPS `/api/incidents/monitor` strictly requires `POST`. Kong forces `GET` to `POST`. |
| **URL Path:** `/va/sov-38alt-crowding` or `/va/sov-38alt-loitering` | **URL Path:** `/api/incidents/monitor` | Kong strips external route path and routes directly to the upstream Service URL. |
| **Auth Header:** `Authorization: Basic <base64>` | **Auth Header:** `Authorization: Basic <base64>` | Preserved. Kong verifies at perimeter and passes through to iMOPS. |
| **Header:** None or `*/*` | **Header:** `Content-Type: application/json` | Kong explicitly declares JSON body format. |
| **Timestamp:** (None from camera) | **Timestamp:** Current Unix epoch (e.g. `1782353500`) | Kong dynamically injects `os.time()` at execution second. |

---

### 4.2 Route 1: Crowding VA Mapping Rule
* **External Public Route:** `GET` or `POST` `http://<KONG_IP>:8088/va/sov-38alt-l4-icc-1-crowding` (alias: `/va/sov-38alt-crowding`)
* **Destination Upstream:** `POST http://host.docker.internal:13000/api/incidents/monitor`
* **Headers to Upstream:**
  ```http
  Authorization: Basic <Base64(username:password)>
  Content-Type: application/json
  ```
* **Generated JSON Payload:**
  ```json
  {
    "site": "SOV @ 38ALT",
    "deviceName": "SOV 38ALT L4 ICC 1 VA CROWDING",
    "incidentType": "CROWDING",
    "timestamp": 1782353500,
    "mode": "incident",
    "metadata": {
      "source": "vizzio_va",
      "webhook": "crowding_sov_38alt_l4_icc_1",
      "associatedCamera": "SOV 38ALT L4 ICC 1"
    }
  }
  ```

---

### 4.3 Route 2: Loitering VA Mapping Rule
* **External Public Route:** `GET` or `POST` `http://<KONG_IP>:8088/va/sov-38alt-l4-lift-lobby-loitering` (alias: `/va/sov-38alt-loitering`)
* **Destination Upstream:** `POST http://host.docker.internal:13000/api/incidents/monitor`
* **Headers to Upstream:**
  ```http
  Authorization: Basic <Base64(username:password)>
  Content-Type: application/json
  ```
* **Generated JSON Payload:**
  ```json
  {
    "site": "SOV @ 38ALT",
    "deviceName": "SOV 38ALT L4 LIFT LOBBY VA LOITERING",
    "incidentType": "LOITERING",
    "timestamp": 1782353500,
    "mode": "incident",
    "metadata": {
      "source": "vizzio_va",
      "webhook": "loitering_sov_38alt_l4_lift_lobby",
      "associatedCamera": "SOV 38ALT L4 Lift Lobby"
    }
  }
  ```

---

## 5. One-Click Automated Setup & Utility Scripts (Recommended)

Automated scripts in `apigw/scripts/` configure or reset the entire gateway in seconds with 100% idempotent upsert logic:

| Script | Platform | What it Does |
| :--- | :--- | :--- |
| **`setup_sicc_va.sh`** / **`.ps1`** | Linux / Windows | Sets up Service, Plugins, Consumer, and all 21 Routes with translators |
| **`test_sicc_va.sh`** / **`.ps1`** | Linux / Windows | Smoke tests health, security boundaries, all 21 routes, and rate limiting |
| **`reset_kong.sh`** / **`.ps1`** | Linux / Windows | Purges all Plugins, Routes, Services, and Consumers (clean reset) |
| **`configure_ufw_kong.sh`** | Linux | Opens ports `8088`, `8443`, `8001`, `8002` in UFW firewall |

---

### 5.1 SICC Automated Setup (`setup_sicc_va.sh` / `setup_sicc_va.ps1`)

Automates the complete end-to-end configuration:
* **Gateway Service:** `imops-sicc-incident-service` -> `http://<UPSTREAM_HOST>:13000/api/incidents/monitor`
* **Service Plugins:** `basic-auth` (hide_credentials: false), `rate-limiting` (60 req/min), `acl` (`sicc_group`)
* **Consumer:** `va_system_consumer` (`vizzio@imops.local` / `xAJHkkm7m3V5MhtF0xGM`)
* **Routes & Dynamic JSON Translators (`post-function`):**
  Configures all 21 distinct routes (`/va/sov-38alt-...`) mapped to the respective camera sensor and incident type, including aliases for routes 1 and 2.

#### How to Run (Linux / macOS):
```bash
# Default (Points upstream to production IP 10.65.51.252:13000):
bash ~/cde/apigw/scripts/setup_sicc_va.sh

# Or pass custom upstream host IP as parameter:
bash ~/cde/apigw/scripts/setup_sicc_va.sh 10.65.51.252

# Or pass custom port:
bash ~/cde/apigw/scripts/setup_sicc_va.sh 10.65.51.252:13000

# Or pass full URL:
bash ~/cde/apigw/scripts/setup_sicc_va.sh http://10.65.51.252:13000/api/incidents/monitor
```

#### How to Run (Windows PowerShell):
```powershell
powershell -ExecutionPolicy Bypass -File c:\Projects\cde\apigw\scripts\setup_sicc_va.ps1 -UpstreamHost 10.65.51.252
```

---

### 5.2 Automated Ingress Smoke & Verification Testing (`test_sicc_va.sh` / `test_sicc_va.ps1`)

Validates the entire deployment in under 5 seconds: checks Kong health, tests security rejection (missing & bad auth), sends `GET` and `POST` probes across all 21 camera routes, and tests rate limiting burst enforcement.

* **Linux / macOS:**
  ```bash
  # Test against localhost:
  bash ~/cde/apigw/scripts/test_sicc_va.sh

  # Or test against remote server IP:
  bash ~/cde/apigw/scripts/test_sicc_va.sh http://10.65.51.252:8088
  ```
* **Windows (PowerShell):**
  ```powershell
  powershell -ExecutionPolicy Bypass -File c:\Projects\cde\apigw\scripts\test_sicc_va.ps1
  
  # Or test remote:
  powershell -ExecutionPolicy Bypass -File c:\Projects\cde\apigw\scripts\test_sicc_va.ps1 -GatewayUrl http://10.65.51.252:8088
  ```

---

### 5.3 Reset / Purge Utility (`reset_kong.sh` / `reset_kong.ps1`)

Quickly wipes all existing Plugins, Routes, Services, and Consumers without needing to delete database volumes or restart containers:

* **Linux:**
  ```bash
  # Force reset (no interactive prompt):
  bash ~/cde/apigw/scripts/reset_kong.sh -y
  ```
* **Windows (PowerShell):**
  ```powershell
  powershell -ExecutionPolicy Bypass -File c:\Projects\cde\apigw\scripts\reset_kong.ps1 -Force
  ```

---

### 5.4 Host UFW Firewall Configuration (`configure_ufw_kong.sh`)

If UFW is active on `sov-webapp`, opens all required proxy and management ports:

```bash
sudo bash ~/cde/apigw/scripts/configure_ufw_kong.sh
```

---

## 6. Step-by-Step Manual Kong Gateway Configuration (Reference / Optional)

You can configure Kong either using the **Command Line (`curl`)** or visually via **Kong Manager UI** (`http://localhost:8002`).

### Approach A: Command Line (Windows & Linux)

#### Step 0 (Optional): Delete All Existing Kong Objects (Clean Reset)
If you ever want to wipe all plugins, routes, services, and consumers to start fresh:

##### Using the Reset Utility Scripts (Recommended):
* **Linux / macOS:**
  ```bash
  bash ~/cde/apigw/scripts/reset_kong.sh -y
  ```
* **Windows (PowerShell):**
  ```powershell
  powershell -ExecutionPolicy Bypass -File c:\Projects\cde\apigw\scripts\reset_kong.ps1 -Force
  ```

##### Or via Direct Terminal One-Liners:
**Windows (PowerShell):**
```powershell
# Delete all Plugins, Routes, Services, and Consumers
(curl.exe -s http://localhost:8001/plugins | ConvertFrom-Json).data | ForEach-Object { curl.exe -s -X DELETE "http://localhost:8001/plugins/$($_.id)" }
(curl.exe -s http://localhost:8001/routes | ConvertFrom-Json).data | ForEach-Object { curl.exe -s -X DELETE "http://localhost:8001/routes/$($_.id)" }
(curl.exe -s http://localhost:8001/services | ConvertFrom-Json).data | ForEach-Object { curl.exe -s -X DELETE "http://localhost:8001/services/$($_.id)" }
(curl.exe -s http://localhost:8001/consumers | ConvertFrom-Json).data | ForEach-Object { curl.exe -s -X DELETE "http://localhost:8001/consumers/$($_.id)" }
```

**Linux / macOS (Bash):**
```bash
# Delete all Plugins, Routes, Services, and Consumers
for id in $(curl -s http://localhost:8001/plugins | grep -o '"id":"[^"]*' | cut -d'"' -f4); do curl -s -X DELETE "http://localhost:8001/plugins/$id"; done
for id in $(curl -s http://localhost:8001/routes | grep -o '"id":"[^"]*' | cut -d'"' -f4); do curl -s -X DELETE "http://localhost:8001/routes/$id"; done
for id in $(curl -s http://localhost:8001/services | grep -o '"id":"[^"]*' | cut -d'"' -f4); do curl -s -X DELETE "http://localhost:8001/services/$id"; done
for id in $(curl -s http://localhost:8001/consumers | grep -o '"id":"[^"]*' | cut -d'"' -f4); do curl -s -X DELETE "http://localhost:8001/consumers/$id"; done
```

---

#### Step 1: Create the Upstream Service
Register the iMOPS Monitor endpoint as the upstream service:
*(Note: Replace `host.docker.internal` with your `<BACKEND_HOST_IP>` if running outside Docker Desktop).*

**Windows (PowerShell):**
```powershell
curl.exe -i -X POST http://localhost:8001/services `
  -d "name=imops-sicc-incident-service" `
  -d "url=http://host.docker.internal:13000/api/incidents/monitor"
```

**Linux / macOS (Bash):**
```bash
curl -i -X POST http://localhost:8001/services \
  -d "name=imops-sicc-incident-service" \
  -d "url=http://host.docker.internal:13000/api/incidents/monitor"
```

---

#### Step 2: Configure Authorization & Throttling on the Service

##### 2.1 Enable `basic-auth` Plugin (Perimeter Authorizer & Pass-Through):
Setting `config.hide_credentials=false` ensures the `Authorization: Basic ...` header is passed directly to the backend.

```powershell
# Windows PowerShell
curl.exe -i -X POST http://localhost:8001/services/imops-sicc-incident-service/plugins `
  -d "name=basic-auth" `
  -d "config.hide_credentials=false"
```
```bash
# Linux / macOS Bash
curl -i -X POST http://localhost:8001/services/imops-sicc-incident-service/plugins \
  -d "name=basic-auth" \
  -d "config.hide_credentials=false"
```

##### 2.2 Enable `rate-limiting` Plugin (Throttler):
```powershell
# Windows PowerShell
curl.exe -i -X POST http://localhost:8001/services/imops-sicc-incident-service/plugins `
  -d "name=rate-limiting" `
  -d "config.minute=60" `
  -d "config.policy=local"
```
```bash
# Linux / macOS Bash
curl -i -X POST http://localhost:8001/services/imops-sicc-incident-service/plugins \
  -d "name=rate-limiting" \
  -d "config.minute=60" \
  -d "config.policy=local"
```

##### 2.3 Create Consumer & Assign Credentials:
Enter your iMOPS username and password:
```powershell
# Windows PowerShell
curl.exe -i -X POST http://localhost:8001/consumers -d "username=va_system_consumer"
curl.exe -i -X POST http://localhost:8001/consumers/va_system_consumer/basic-auth `
  -d "username=vizzio@imops.local" `
  -d "password=xAJHkkm7m3V5MhtF0xGM"
```
```bash
# Linux / macOS Bash
curl -i -X POST http://localhost:8001/consumers -d "username=va_system_consumer"
curl -i -X POST http://localhost:8001/consumers/va_system_consumer/basic-auth \
  -d "username=vizzio@imops.local" \
  -d "password=xAJHkkm7m3V5MhtF0xGM"
```

---

#### Step 3: Configure Route 1 — Crowding VA

##### 3.1 Create Public Route:
```powershell
# Windows PowerShell
curl.exe -i -X POST http://localhost:8001/services/imops-sicc-incident-service/routes `
  -d "name=va-crowding-sov-38alt" `
  -d "paths[]=/va/sov-38alt-crowding" `
  -d "methods[]=GET" `
  -d "methods[]=POST" `
  -d "strip_path=true"
```
```bash
# Linux / macOS Bash
curl -i -X POST http://localhost:8001/services/imops-sicc-incident-service/routes \
  -d "name=va-crowding-sov-38alt" \
  -d "paths[]=/va/sov-38alt-crowding" \
  -d "methods[]=GET" \
  -d "methods[]=POST" \
  -d "strip_path=true"
```

##### 3.2 Attach Kong Translator Plugin (`pre-function`):
This script converts `GET` to `POST`, sets `Content-Type: application/json`, and injects the live Crowding JSON payload with the current timestamp.

**Windows (PowerShell — Uses native heredoc to prevent quote escaping issues):**
```powershell
$luaCrowding = @'
local now = os.time()
kong.service.request.set_method("POST")
kong.service.request.set_header("Authorization", "Basic dml6emlvQGltb3BzLmxvY2FsOnhBSkhra203bTNWNU1odEYweEdN")
kong.service.request.set_header("Content-Type", "application/json")
local b = string.format('{"site":"SOV @ 38ALT","deviceName":"SOV 38ALT L4 ICC 1 VA CROWDING","incidentType":"CROWDING","timestamp":%d,"mode":"incident","metadata":{"source":"vizzio_va","webhook":"crowding_sov_38alt_l4_icc_1","associatedCamera":"SOV 38ALT L4 ICC 1"}}', now)
kong.service.request.set_raw_body(b)
'@

Invoke-RestMethod -Uri "http://localhost:8001/routes/va-crowding-sov-38alt/plugins" -Method Post -Body @{
    name = "pre-function"
    "config.access[]" = $luaCrowding
}
```

**Linux / macOS (Bash):**
```bash
curl -i -X POST http://localhost:8001/routes/va-crowding-sov-38alt/plugins \
  -d "name=pre-function" \
  --data-urlencode "config.access[]=local now = os.time(); kong.service.request.set_method('POST'); kong.service.request.set_header('Authorization', 'Basic dml6emlvQGltb3BzLmxvY2FsOnhBSkhra203bTNWNU1odEYweEdN'); kong.service.request.set_header('Content-Type', 'application/json'); local b = string.format('{\"site\":\"SICC\",\"deviceName\":\"SOV 38ALT L4 ICC 1 VA CROWDING\",\"incidentType\":\"CROWDING\",\"timestamp\":%d,\"mode\":\"incident\",\"metadata\":{\"source\":\"vizzio_va\",\"webhook\":\"crowding_sov_38alt_l4_icc_1\",\"associatedCamera\":\"SOV 38ALT L4 ICC 1\"}}', now); kong.service.request.set_raw_body(b);"
```

---

#### Step 4: Configure Route 2 — Loitering VA

##### 4.1 Create Public Route:
```powershell
# Windows PowerShell
curl.exe -i -X POST http://localhost:8001/services/imops-sicc-incident-service/routes `
  -d "name=va-loitering-sov-38alt" `
  -d "paths[]=/va/sov-38alt-loitering" `
  -d "methods[]=GET" `
  -d "methods[]=POST" `
  -d "strip_path=true"
```
```bash
# Linux / macOS Bash
curl -i -X POST http://localhost:8001/services/imops-sicc-incident-service/routes \
  -d "name=va-loitering-sov-38alt" \
  -d "paths[]=/va/sov-38alt-loitering" \
  -d "methods[]=GET" \
  -d "methods[]=POST" \
  -d "strip_path=true"
```

##### 4.2 Attach Kong Translator Plugin (`pre-function`):
This script converts `GET` to `POST`, sets `Content-Type: application/json`, and injects the live Loitering JSON payload with the current timestamp:

**Windows (PowerShell — Uses native heredoc to prevent quote escaping issues):**
```powershell
$luaLoitering = @'
local now = os.time()
kong.service.request.set_method("POST")
kong.service.request.set_header("Authorization", "Basic dml6emlvQGltb3BzLmxvY2FsOnhBSkhra203bTNWNU1odEYweEdN")
kong.service.request.set_header("Content-Type", "application/json")
local b = string.format('{"site":"SOV @ 38ALT","deviceName":"SOV 38ALT L4 LIFT LOBBY VA LOITERING","incidentType":"LOITERING","timestamp":%d,"mode":"incident","metadata":{"source":"vizzio_va","webhook":"loitering_sov_38alt_l4_lift_lobby","associatedCamera":"SOV 38ALT L4 Lift Lobby"}}', now)
kong.service.request.set_raw_body(b)
'@

Invoke-RestMethod -Uri "http://localhost:8001/routes/va-loitering-sov-38alt/plugins" -Method Post -Body @{
    name = "pre-function"
    "config.access[]" = $luaLoitering
}
```

**Linux / macOS (Bash):**
```bash
curl -i -X POST http://localhost:8001/routes/va-loitering-sov-38alt/plugins \
  -d "name=pre-function" \
  --data-urlencode "config.access[]=local now = os.time(); kong.service.request.set_method('POST'); kong.service.request.set_header('Authorization', 'Basic dml6emlvQGltb3BzLmxvY2FsOnhBSkhra203bTNWNU1odEYweEdN'); kong.service.request.set_header('Content-Type', 'application/json'); local b = string.format('{\"site\":\"SICC\",\"deviceName\":\"SOV 38ALT L4 LIFT LOBBY VA LOITERING\",\"incidentType\":\"LOITERING\",\"timestamp\":%d,\"mode\":\"incident\",\"metadata\":{\"source\":\"vizzio_va\",\"webhook\":\"loitering_sov_38alt_l4_lift_lobby\",\"associatedCamera\":\"SOV 38ALT L4 Lift Lobby\"}}', now); kong.service.request.set_raw_body(b);"
```

---

### Approach B: Kong Manager UI (`http://localhost:8002`)

1. **Create Gateway Service:**
   - Go to **Gateway Services** -> Click **New Gateway Service**.
   - **Name:** `imops-sicc-incident-service`
   - **Upstream URL:** `http://host.docker.internal:13000/api/incidents/monitor`
   - Click **Save**.

2. **Add Security & Throttling Plugins:**
   - Under `imops-sicc-incident-service` -> **Plugins** -> **Add Plugin** -> Select **Basic Auth**.
   - Set **Hide Credentials** to `false` (so iMOPS receives the Basic Auth header). Click **Save**.
   - Click **Add Plugin** again -> Select **Rate Limiting**.
   - Set **Config.Minute** to `60`. Click **Save**.

3. **Add Consumer & Credentials:**
   - Go to **Consumers** -> **New Consumer** -> Username: `va_system_consumer`. Click **Save**.
   - Open `va_system_consumer` -> **Credentials** tab -> **Basic Auth** -> **New Basic Auth Credential**.
   - Enter **Username:** `vizzio@imops.local` and **Password:** `xAJHkkm7m3V5MhtF0xGM`. Click **Save**.

4. **Add Crowding Route:**
   - Under `imops-sicc-incident-service` -> **Routes** -> **New Route**.
   - **Name:** `va-crowding-sov-38alt` | **Paths:** `/va/sov-38alt-crowding` | Check **GET** and **POST**.
   - **Strip Path:** Enable (`true`). Click **Save**.
   - Open this route -> **Plugins** -> **Add Plugin** -> Select **Pre-Function**.
   - In **Config.Access**, paste this exact snippet:
     ```lua
     local now = os.time()
     kong.service.request.set_method("POST")
     kong.service.request.set_header("Authorization", "Basic dml6emlvQGltb3BzLmxvY2FsOnhBSkhra203bTNWNU1odEYweEdN")
     kong.service.request.set_header("Content-Type", "application/json")
     local b = string.format('{"site":"SOV @ 38ALT","deviceName":"SOV 38ALT L4 ICC 1 VA CROWDING","incidentType":"CROWDING","timestamp":%d,"mode":"incident","metadata":{"source":"vizzio_va","webhook":"crowding_sov_38alt_l4_icc_1","associatedCamera":"SOV 38ALT L4 ICC 1"}}', now)
     kong.service.request.set_raw_body(b)
     ```
   - Click **Save**.

5. **Add Loitering Route:**
   - Under `imops-sicc-incident-service` -> **Routes** -> **New Route**.
   - **Name:** `va-loitering-sov-38alt` | **Paths:** `/va/sov-38alt-loitering` | Check **GET** and **POST**.
   - **Strip Path:** Enable (`true`). Click **Save**.
   - Open this route -> **Plugins** -> **Add Plugin** -> Select **Pre-Function**.
   - In **Config.Access**, paste this exact snippet:
     ```lua
     local now = os.time()
     kong.service.request.set_method("POST")
     kong.service.request.set_header("Authorization", "Basic dml6emlvQGltb3BzLmxvY2FsOnhBSkhra203bTNWNU1odEYweEdN")
     kong.service.request.set_header("Content-Type", "application/json")
     local b = string.format('{"site":"SOV @ 38ALT","deviceName":"SOV 38ALT L4 LIFT LOBBY VA LOITERING","incidentType":"LOITERING","timestamp":%d,"mode":"incident","metadata":{"source":"vizzio_va","webhook":"loitering_sov_38alt_l4_lift_lobby","associatedCamera":"SOV 38ALT L4 Lift Lobby"}}', now)
     kong.service.request.set_raw_body(b)
     ```
   - Click **Save**.

---

## 7. How to Add More VAs in the Future (No Backend Code Changes)

When a 3rd or 4th camera comes along (e.g. `INTRUSION_VA-SOV_38ALT_Roof`):
**You do NOT modify iMOPS.** You simply register the new Route and its JSON payload in Kong:

### Windows (PowerShell):
```powershell
# 1. Create Route
curl.exe -i -X POST http://localhost:8001/services/imops-sicc-incident-service/routes `
  -d "name=va-intrusion-sov-roof" `
  -d "paths[]=/va/sov-roof-intrusion" `
  -d "methods[]=GET" `
  -d "methods[]=POST" `
  -d "strip_path=true"

# 2. Attach Translator Plugin
$luaIntrusion = @'
local now = os.time()
kong.service.request.set_method("POST")
kong.service.request.set_header("Authorization", "Basic dml6emlvQGltb3BzLmxvY2FsOnhBSkhra203bTNWNU1odEYweEdN")
kong.service.request.set_header("Content-Type", "application/json")
local b = string.format('{"site":"SOV","deviceName":"INTRUSION_VA-SOV_38ALT_Roof","incidentType":"INTRUSION","timestamp":%d,"mode":"incident","metadata":{"source":"vizzio_va","webhook":"intrusion_sov_roof","associatedCamera":"SOV 38ALT Roof"}}', now)
kong.service.request.set_raw_body(b)
'@

Invoke-RestMethod -Uri "http://localhost:8001/routes/va-intrusion-sov-roof/plugins" -Method Post -Body @{
    name = "pre-function"
    "config.access[]" = $luaIntrusion
}
```

### Linux / macOS (Bash):
```bash
# 1. Create Route
curl -i -X POST http://localhost:8001/services/imops-sicc-incident-service/routes \
  -d "name=va-intrusion-sov-roof" \
  -d "paths[]=/va/sov-roof-intrusion" \
  -d "methods[]=GET" \
  -d "methods[]=POST" \
  -d "strip_path=true"

# 2. Attach Translator Plugin
curl -i -X POST http://localhost:8001/routes/va-intrusion-sov-roof/plugins \
  -d "name=pre-function" \
  --data-urlencode "config.access[]=local now = os.time(); kong.service.request.set_method('POST'); kong.service.request.set_header('Authorization', 'Basic dml6emlvQGltb3BzLmxvY2FsOnhBSkhra203bTNWNU1odEYweEdN'); kong.service.request.set_header('Content-Type', 'application/json'); local b = string.format('{\"site\":\"SOV\",\"deviceName\":\"INTRUSION_VA-SOV_38ALT_Roof\",\"incidentType\":\"INTRUSION\",\"timestamp\":%d,\"mode\":\"incident\",\"metadata\":{\"source\":\"vizzio_va\",\"webhook\":\"intrusion_sov_roof\",\"associatedCamera\":\"SOV 38ALT Roof\"}}', now); kong.service.request.set_raw_body(b);"
```

---

## 8. How to Update or Rotate Consumer Credentials

If you ever need to change or rotate the username and password for a consumer (e.g. updating from an old account to `vizzio@imops.local:xAJHkkm7m3V5MhtF0xGM`):

### Option A: Command Line (`curl`)

#### 1. List existing credentials to find the Credential ID:
```powershell
# Windows
curl.exe -s http://localhost:8001/consumers/va_system_consumer/basic-auth
```
```bash
# Linux
curl -s http://localhost:8001/consumers/va_system_consumer/basic-auth
```
*(Copy the `"id"` from the output, e.g. `e6fb16a0-a2fb-4742-9711-92e48bd93648`).*

#### 2. Delete the old credential:
```powershell
# Windows
curl.exe -i -X DELETE http://localhost:8001/consumers/va_system_consumer/basic-auth/<OLD_CREDENTIAL_ID>
```
```bash
# Linux
curl -i -X DELETE http://localhost:8001/consumers/va_system_consumer/basic-auth/<OLD_CREDENTIAL_ID>
```

#### 3. Add the new credential:
```powershell
# Windows PowerShell
curl.exe -i -X POST http://localhost:8001/consumers/va_system_consumer/basic-auth `
  -d "username=vizzio@imops.local" `
  -d "password=xAJHkkm7m3V5MhtF0xGM"
```
```bash
# Linux / macOS Bash
curl -i -X POST http://localhost:8001/consumers/va_system_consumer/basic-auth \
  -d "username=vizzio@imops.local" \
  -d "password=xAJHkkm7m3V5MhtF0xGM"
```

---

### Option B: Kong Manager UI (`http://localhost:8002`)
1. Open **[http://localhost:8002](http://localhost:8002)** in your browser.
2. Click **Consumers** in the left navigation menu.
3. Click on **`va_system_consumer`**.
4. Go to the **Credentials** tab (or **Basic Auth** sub-tab).
5. Click the trash icon next to the old credential to delete it.
6. Click **New Basic Auth Credential** ➔ enter `vizzio@imops.local` and `xAJHkkm7m3V5MhtF0xGM` ➔ click **Save**.

---

## 9. Verification & Testing

This section provides a **complete, exhaustive test suite** for verifying the Kong Gateway ingress deployment across all **21 production VA cameras**, security boundaries, HTTP method translations, rate limiting, and downstream backend persistence.

---

### 9.1 Test Overview & Credentials

* **Ingress Gateway Base URL:** `http://<KONG_HOST>:8088` (or `http://localhost:8088` locally, `http://10.65.51.252:8088` on production)
* **Ingress Consumer:** `va_system_consumer`
* **HTTP Basic Auth Username:** `vizzio@imops.local`
* **HTTP Basic Auth Password:** `xAJHkkm7m3V5MhtF0xGM`
* **Base64 Header:** `Authorization: Basic dml6emlvQGltb3BzLmxvY2FsOnhBSkhra203bTNWNU1odEYweEdN`
* **ACL Group:** `sicc_group`
* **Downstream Target:** `http://<BACKEND_HOST_IP>:13000/api/incidents/monitor`

---

### 9.2 One-Click Automated Verification Smoke Tests (Recommended)

Run the automated test suite to validate gateway health, security rejection, all 21 camera routes (`GET` & `POST`), and rate limiting burst protection in under 5 seconds:

#### Linux / macOS (Bash):
```bash
# Test local gateway:
bash ~/cde/apigw/scripts/test_sicc_va.sh

# Or test remote host:
bash ~/cde/apigw/scripts/test_sicc_va.sh http://10.65.51.252:8088
```

#### Windows (PowerShell):
```powershell
# Test local gateway:
powershell -ExecutionPolicy Bypass -File c:\Projects\cde\apigw\scripts\test_sicc_va.ps1

# Or test remote host:
powershell -ExecutionPolicy Bypass -File c:\Projects\cde\apigw\scripts\test_sicc_va.ps1 -GatewayUrl http://10.65.51.252:8088
```

#### Instant Terminal One-Liner (No Script Required):
**Windows (PowerShell):**
```powershell
@(
  "/va/sov-38alt-l4-icc-1-crowding",
  "/va/sov-38alt-l4-lift-lobby-loitering",
  "/va/sov-38alt-main-gate-smoking",
  "/va/sov-38alt-main-gate-fire",
  "/va/sov-38alt-carpark-lot-1-illegal-parking",
  "/va/sov-38alt-l1-lift-lobby-loitering",
  "/va/sov-38alt-l4-corridor-o-s-war-room-loitering",
  "/va/sov-38alt-l4-interlock-loitering",
  "/va/sov-38alt-l5-corridor-loitering",
  "/va/sov-38alt-side-fencing-intrusion",
  "/va/sov-38alt-side-fencing-smoking",
  "/va/sov-38alt-side-fencing-fire",
  "/va/sov-38alt-roof-top-loitering",
  "/va/sov-38alt-l2-lift-lobby-loitering",
  "/va/sov-38alt-l3-lift-lobby-loitering",
  "/va/sov-38alt-l2-main-lobby-loitering",
  "/va/sov-38alt-l2-reception-loitering",
  "/va/sov-38alt-main-road-loitering",
  "/va/sov-38alt-l6-lift-lobby-loitering",
  "/va/sov-38alt-l5-o-s-cyber-room-loitering",
  "/va/sov-38alt-main-gate-perimeter-intrusion"
) | ForEach-Object {
    $code = (curl.exe -s -o /dev/null -w "%{http_code}" "http://localhost:8088$_" -u "vizzio@imops.local:xAJHkkm7m3V5MhtF0xGM")
    Write-Host "$_ -> HTTP $code" -ForegroundColor $(if ($code -eq 200) { "Green" } else { "Red" })
}
```

**Linux / macOS (Bash):**
```bash
for route in \
  /va/sov-38alt-l4-icc-1-crowding \
  /va/sov-38alt-l4-lift-lobby-loitering \
  /va/sov-38alt-main-gate-smoking \
  /va/sov-38alt-main-gate-fire \
  /va/sov-38alt-carpark-lot-1-illegal-parking \
  /va/sov-38alt-l1-lift-lobby-loitering \
  /va/sov-38alt-l4-corridor-o-s-war-room-loitering \
  /va/sov-38alt-l4-interlock-loitering \
  /va/sov-38alt-l5-corridor-loitering \
  /va/sov-38alt-side-fencing-intrusion \
  /va/sov-38alt-side-fencing-smoking \
  /va/sov-38alt-side-fencing-fire \
  /va/sov-38alt-roof-top-loitering \
  /va/sov-38alt-l2-lift-lobby-loitering \
  /va/sov-38alt-l3-lift-lobby-loitering \
  /va/sov-38alt-l2-main-lobby-loitering \
  /va/sov-38alt-l2-reception-loitering \
  /va/sov-38alt-main-road-loitering \
  /va/sov-38alt-l6-lift-lobby-loitering \
  /va/sov-38alt-l5-o-s-cyber-room-loitering \
  /va/sov-38alt-main-gate-perimeter-intrusion; do
    code=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8088$route" -u "vizzio@imops.local:xAJHkkm7m3V5MhtF0xGM")
    echo "$route -> HTTP $code"
done
```

---

### 9.3 Complete 21-Route Test Commands & Verification Matrix

Every route accepts both **`GET`** and **`POST`** methods and transforms into the standardized incident schema on the upstream backend:

| # | Public Ingress URL Path | Incident Type | Camera / Sensor | Expected HTTP Code | Test Command (Windows / Linux) |
|---|---|---|---|---|---|
| **1** | `/va/sov-38alt-l4-icc-1-crowding`<br>*(alias: `/va/sov-38alt-crowding`)* | `CROWDING` | SOV 38ALT L4 ICC 1 | `200 OK` | `curl -i -X GET http://localhost:8088/va/sov-38alt-l4-icc-1-crowding -u "vizzio@imops.local:xAJHkkm7m3V5MhtF0xGM"` |
| **2** | `/va/sov-38alt-l4-lift-lobby-loitering`<br>*(alias: `/va/sov-38alt-loitering`)* | `LOITERING` | SOV 38ALT L4 Lift Lobby | `200 OK` | `curl -i -X GET http://localhost:8088/va/sov-38alt-l4-lift-lobby-loitering -u "vizzio@imops.local:xAJHkkm7m3V5MhtF0xGM"` |
| **3** | `/va/sov-38alt-main-gate-smoking` | `SMOKING` | SOV 38ALT Main Gate | `200 OK` | `curl -i -X GET http://localhost:8088/va/sov-38alt-main-gate-smoking -u "vizzio@imops.local:xAJHkkm7m3V5MhtF0xGM"` |
| **4** | `/va/sov-38alt-main-gate-fire` | `FIRE` | SOV 38ALT Main Gate | `200 OK` | `curl -i -X GET http://localhost:8088/va/sov-38alt-main-gate-fire -u "vizzio@imops.local:xAJHkkm7m3V5MhtF0xGM"` |
| **5** | `/va/sov-38alt-carpark-lot-1-illegal-parking` | `ILLEGAL_PARKING` | SOV 38ALT Carpark Lot 1 | `200 OK` | `curl -i -X GET http://localhost:8088/va/sov-38alt-carpark-lot-1-illegal-parking -u "vizzio@imops.local:xAJHkkm7m3V5MhtF0xGM"` |
| **6** | `/va/sov-38alt-l1-lift-lobby-loitering` | `LOITERING` | SOV 38ALT L1 Lift Lobby | `200 OK` | `curl -i -X GET http://localhost:8088/va/sov-38alt-l1-lift-lobby-loitering -u "vizzio@imops.local:xAJHkkm7m3V5MhtF0xGM"` |
| **7** | `/va/sov-38alt-l4-corridor-o-s-war-room-loitering` | `LOITERING` | SOV 38ALT L4 Corridor o/s War Room | `200 OK` | `curl -i -X GET http://localhost:8088/va/sov-38alt-l4-corridor-o-s-war-room-loitering -u "vizzio@imops.local:xAJHkkm7m3V5MhtF0xGM"` |
| **8** | `/va/sov-38alt-l4-interlock-loitering` | `LOITERING` | SOV 38ALT L4 Interlock | `200 OK` | `curl -i -X GET http://localhost:8088/va/sov-38alt-l4-interlock-loitering -u "vizzio@imops.local:xAJHkkm7m3V5MhtF0xGM"` |
| **9** | `/va/sov-38alt-l5-corridor-loitering` | `LOITERING` | SOV 38ALT L5 Corridor | `200 OK` | `curl -i -X GET http://localhost:8088/va/sov-38alt-l5-corridor-loitering -u "vizzio@imops.local:xAJHkkm7m3V5MhtF0xGM"` |
| **10** | `/va/sov-38alt-side-fencing-intrusion` | `INTRUSION` | SOV 38ALT Side Fencing | `200 OK` | `curl -i -X GET http://localhost:8088/va/sov-38alt-side-fencing-intrusion -u "vizzio@imops.local:xAJHkkm7m3V5MhtF0xGM"` |
| **11** | `/va/sov-38alt-side-fencing-smoking` | `SMOKING` | SOV 38ALT Side Fencing | `200 OK` | `curl -i -X GET http://localhost:8088/va/sov-38alt-side-fencing-smoking -u "vizzio@imops.local:xAJHkkm7m3V5MhtF0xGM"` |
| **12** | `/va/sov-38alt-side-fencing-fire` | `FIRE` | SOV 38ALT Side Fencing | `200 OK` | `curl -i -X GET http://localhost:8088/va/sov-38alt-side-fencing-fire -u "vizzio@imops.local:xAJHkkm7m3V5MhtF0xGM"` |
| **13** | `/va/sov-38alt-roof-top-loitering` | `LOITERING` | SOV 38ALT Roof Top | `200 OK` | `curl -i -X GET http://localhost:8088/va/sov-38alt-roof-top-loitering -u "vizzio@imops.local:xAJHkkm7m3V5MhtF0xGM"` |
| **14** | `/va/sov-38alt-l2-lift-lobby-loitering` | `LOITERING` | SOV 38ALT L2 Lift Lobby | `200 OK` | `curl -i -X GET http://localhost:8088/va/sov-38alt-l2-lift-lobby-loitering -u "vizzio@imops.local:xAJHkkm7m3V5MhtF0xGM"` |
| **15** | `/va/sov-38alt-l3-lift-lobby-loitering` | `LOITERING` | SOV 38ALT L3 Lift Lobby | `200 OK` | `curl -i -X GET http://localhost:8088/va/sov-38alt-l3-lift-lobby-loitering -u "vizzio@imops.local:xAJHkkm7m3V5MhtF0xGM"` |
| **16** | `/va/sov-38alt-l2-main-lobby-loitering` | `LOITERING` | SOV 38ALT L2 Main Lobby | `200 OK` | `curl -i -X GET http://localhost:8088/va/sov-38alt-l2-main-lobby-loitering -u "vizzio@imops.local:xAJHkkm7m3V5MhtF0xGM"` |
| **17** | `/va/sov-38alt-l2-reception-loitering` | `LOITERING` | SOV 38ALT L2 Reception | `200 OK` | `curl -i -X GET http://localhost:8088/va/sov-38alt-l2-reception-loitering -u "vizzio@imops.local:xAJHkkm7m3V5MhtF0xGM"` |
| **18** | `/va/sov-38alt-main-road-loitering` | `LOITERING` | SOV 38ALT Main Road | `200 OK` | `curl -i -X GET http://localhost:8088/va/sov-38alt-main-road-loitering -u "vizzio@imops.local:xAJHkkm7m3V5MhtF0xGM"` |
| **19** | `/va/sov-38alt-l6-lift-lobby-loitering` | `LOITERING` | SOV 38ALT L6 Lift Lobby | `200 OK` | `curl -i -X GET http://localhost:8088/va/sov-38alt-l6-lift-lobby-loitering -u "vizzio@imops.local:xAJHkkm7m3V5MhtF0xGM"` |
| **20** | `/va/sov-38alt-l5-o-s-cyber-room-loitering` | `LOITERING` | SOV 38ALT L5 o/s Cyber Room | `200 OK` | `curl -i -X GET http://localhost:8088/va/sov-38alt-l5-o-s-cyber-room-loitering -u "vizzio@imops.local:xAJHkkm7m3V5MhtF0xGM"` |
| **21** | `/va/sov-38alt-main-gate-perimeter-intrusion` | `INTRUSION` | SOV 38ALT Main Gate Perimeter | `200 OK` | `curl -i -X GET http://localhost:8088/va/sov-38alt-main-gate-perimeter-intrusion -u "vizzio@imops.local:xAJHkkm7m3V5MhtF0xGM"` |

---

### 9.4 Security & Access Control Boundary Tests

Kong Gateway enforces strict authentication at the network perimeter via `basic-auth` and `acl` plugins. Verify that unauthorized traffic is stopped cold at the gateway without ever reaching the iMOPS backend.

#### Test 4.1: Valid Basic Authentication Credentials (PASS)
```bash
curl -i -X GET http://localhost:8088/va/sov-38alt-l4-icc-1-crowding \
  -u "vizzio@imops.local:xAJHkkm7m3V5MhtF0xGM"
```
**Expected Response:** `HTTP/1.1 200 OK` with JSON incident response.

#### Test 4.2: Missing Authentication Header (REJECT)
```bash
curl -i -X GET http://localhost:8088/va/sov-38alt-l4-icc-1-crowding
```
**Expected Response:** `HTTP/1.1 401 Unauthorized`
```json
{
  "message": "Unauthorized"
}
```

#### Test 4.3: Invalid / Corrupted Credentials (REJECT)
```bash
curl -i -X GET http://localhost:8088/va/sov-38alt-l4-icc-1-crowding \
  -u "wrong_user:wrong_password"
```
**Expected Response:** `HTTP/1.1 401 Unauthorized`
```json
{
  "message": "Invalid authentication credentials"
}
```

#### Test 4.4: ACL Authorization Restriction (REJECT)
If a consumer has valid Basic Auth credentials but does NOT belong to the `sicc_group` ACL:
```bash
curl -i -X GET http://localhost:8088/va/sov-38alt-l4-icc-1-crowding \
  -u "other_consumer@imops.local:some_password"
```
**Expected Response:** `HTTP/1.1 403 Forbidden`
```json
{
  "message": "You cannot consume this service"
}
```

---

### 9.5 HTTP Method Translation & Negative Method Verification

Camera hardware may trigger alerts via `GET` (web query) or `POST` (webhook push). Kong accepts both and normalizes them into upstream `POST` requests while rejecting non-supported HTTP verbs.

#### Test 5.1: Camera `GET` Trigger Translation
```bash
curl -i -X GET http://localhost:8088/va/sov-38alt-l4-icc-1-crowding \
  -u "vizzio@imops.local:xAJHkkm7m3V5MhtF0xGM"
```
* **Inbound to Kong:** `GET /va/sov-38alt-l4-icc-1-crowding` (No body)
* **Outbound from Kong:** `POST /api/incidents/monitor` (Injected JSON payload & Live Timestamp)
* **Result:** `HTTP/1.1 200 OK`

#### Test 5.2: Camera `POST` Trigger Passthrough
```bash
curl -i -X POST http://localhost:8088/va/sov-38alt-l4-icc-1-crowding \
  -u "vizzio@imops.local:xAJHkkm7m3V5MhtF0xGM"
```
* **Result:** `HTTP/1.1 200 OK`

#### Test 5.3: Disallowed HTTP Verbs (`PUT`, `DELETE`, `PATCH`)
```bash
curl -i -X DELETE http://localhost:8088/va/sov-38alt-l4-icc-1-crowding \
  -u "vizzio@imops.local:xAJHkkm7m3V5MhtF0xGM"
```
**Expected Response:** `HTTP/1.1 405 Method Not Allowed` or `HTTP/1.1 404 Not Found` (Routing rejects methods outside `["GET", "POST"]`).

---

### 9.6 Rate Limiting, Throttling & Header Verification

Kong enforces a quota of **60 requests per minute** per consumer to safeguard iMOPS from camera alert flooding loops.

#### Test 6.1: Burst Rate Limit Trigger (Returns HTTP 429)
**Windows (PowerShell):**
```powershell
1..65 | ForEach-Object { 
    curl.exe -s -o /dev/null -w "%{http_code}`n" http://localhost:8088/va/sov-38alt-l4-icc-1-crowding -u "vizzio@imops.local:xAJHkkm7m3V5MhtF0xGM" 
}
```
**Linux / macOS (Bash):**
```bash
for i in {1..65}; do 
    curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8088/va/sov-38alt-l4-icc-1-crowding -u "vizzio@imops.local:xAJHkkm7m3V5MhtF0xGM"
done
```
* Requests 1 through 60 return: **`200`**
* Request 61+ returns: **`429 Too Many Requests`** with response:
  ```json
  {
    "message": "API rate limit exceeded"
  }
  ```

#### Test 6.2: Inspect Rate Limit Response Headers
Inspect the rate limit tracking headers returned by Kong on every request:
```bash
curl -i -X GET http://localhost:8088/va/sov-38alt-l4-icc-1-crowding \
  -u "vizzio@imops.local:xAJHkkm7m3V5MhtF0xGM" | grep -i ratelimit
```
**Headers Output:**
```http
RateLimit-Limit: 60
RateLimit-Remaining: 59
RateLimit-Reset: 42
X-RateLimit-Limit-Minute: 60
X-RateLimit-Remaining-Minute: 59
```

#### Test 6.3: How to Adjust or Customize Rate Limits
To change the threshold (e.g. increase to 120 req/min) with **zero downtime**:

* **Via Kong Manager UI (`http://localhost:8002`):**
  1. Open `http://localhost:8002` ➔ **Gateway Services** ➔ click `imops-sicc-incident-service`.
  2. Go to **Plugins** ➔ find `rate-limiting` ➔ click **Edit**.
  3. Modify **Minute** to `120` ➔ click **Save Changes**.

* **Via Command Line (`curl`):**
  ```powershell
  # PowerShell: Retrieve plugin ID and update to 120 req/min
  $pluginId = (Invoke-RestMethod http://localhost:8001/services/imops-sicc-incident-service/plugins).data | 
      Where-Object { $_.name -eq "rate-limiting" } | Select-Object -ExpandProperty id
  curl.exe -i -X PATCH "http://localhost:8001/plugins/$pluginId" -d "config.minute=120"
  ```
  ```bash
  # Bash: Retrieve plugin ID and update to 120 req/min
  PLUGIN_ID=$(curl -s http://localhost:8001/services/imops-sicc-incident-service/plugins | grep -o '"id":"[^"]*' | head -n 1 | cut -d'"' -f4)
  curl -i -X PATCH "http://localhost:8001/plugins/$PLUGIN_ID" -d "config.minute=120"
  ```

---

### 9.7 Dynamic Payload, Headers & Live Timestamp Verification

Verify that Kong dynamically computes `os.time()`, attaches the JSON body, and sets the required HTTP headers before dispatching to the iMOPS upstream.

#### Expected Successful iMOPS JSON Response:
When Kong successfully transforms and forwards a trigger to `/api/incidents/monitor`, iMOPS returns `HTTP 200 OK` or `201 Created`:
```json
{
  "success": true,
  "action": "created",
  "incident": {
    "_id": "66e01a2b...",
    "title": "CROWDING: SOV 38ALT L4 ICC 1 VA CROWDING",
    "status": "new",
    "priority": "medium",
    "site": "SOV @ 38ALT",
    "incidentType": "CROWDING",
    "source": {
      "deviceName": "SOV 38ALT L4 ICC 1 VA CROWDING"
    },
    "metadata": {
      "source": "vizzio_va",
      "webhook": "crowding_sov_38alt_l4_icc_1",
      "associatedCamera": "SOV 38ALT L4 ICC 1"
    },
    "createdAt": "2026-09-11T14:19:50.000Z"
  }
}
```

#### Verifying Dynamic Timestamp Freshness:
The timestamp in the incident record corresponds to the exact second Kong received the request:
```bash
# Check current system timestamp vs timestamp recorded in incident:
date +%s
```

---

### 9.8 Downstream Backend & Database Verification

Confirm that incident records triggered via Kong are persisted into the production database and broadcast across iMOPS operator workstations.

#### 1. Direct MongoDB Query (Inside Container):
Run on the server hosting the iMOPS backend:
```bash
docker exec -it imops-mongo mongosh imops --eval '
  db.incidents.find({ site: "SOV @ 38ALT" })
    .sort({ _id: -1 })
    .limit(5)
    .projection({ title: 1, incidentType: 1, site: 1, createdAt: 1, "metadata.webhook": 1 })
'
```
**Expected Output:**
```javascript
[
  {
    _id: ObjectId("..."),
    title: 'CROWDING: SOV 38ALT L4 ICC 1 VA CROWDING',
    incidentType: 'CROWDING',
    site: 'SOV @ 38ALT',
    metadata: { webhook: 'crowding_sov_38alt_l4_icc_1' },
    createdAt: ISODate("2026-09-11T...")
  }
]
```

#### 2. Real-Time Web UI Incident Monitor Audit:
1. Log in to the iMOPS Web Portal at `http://<BACKEND_HOST_IP>:13000`.
2. Navigate to **Incident Monitor** or **Operations Dashboard**.
3. Fire a test alert using curl:
   ```bash
   curl -s -X GET http://localhost:8088/va/sov-38alt-side-fencing-fire -u "vizzio@imops.local:xAJHkkm7m3V5MhtF0xGM"
   ```
4. Confirm the incident appears in real time on the dashboard with `site: SOV @ 38ALT` and `incidentType: FIRE`.

---

### 9.9 Fault Tolerance & Negative Edge Cases

#### Test 9.1: Unmatched Ingress Route / Typo in URL (HTTP 404)
```bash
curl -i -X GET http://localhost:8088/va/invalid-camera-path \
  -u "vizzio@imops.local:xAJHkkm7m3V5MhtF0xGM"
```
**Expected Response:** `HTTP/1.1 404 Not Found`
```json
{
  "message": "no Route matched with those values"
}
```

#### Test 9.2: Upstream Backend Unreachable / Down (HTTP 502 / 504)
If the downstream iMOPS container is stopped (`docker stop imops-backend`):
```bash
curl -i -X GET http://localhost:8088/va/sov-38alt-l4-icc-1-crowding \
  -u "vizzio@imops.local:xAJHkkm7m3V5MhtF0xGM"
```
**Expected Response:** `HTTP/1.1 502 Bad Gateway` or `HTTP/1.1 504 Gateway Timeout`
```json
{
  "message": "An invalid response was received from the upstream server"
}
```

#### Test 9.3: Kong Admin Health & Uptime Probe
Verify Kong process status via the Admin API:
```bash
curl -i -X GET http://localhost:8001/status
```
**Expected Response:** `HTTP/1.1 200 OK`
```json
{
  "server": {
    "total_requests": 1420,
    "connections_active": 1,
    "connections_accepted": 1420,
    "connections_handled": 1420,
    "connections_reading": 0,
    "connections_writing": 1,
    "connections_waiting": 0
  },
  "database": {
    "reachable": true
  }
}
```

---

### 9.10 CLI Gateway Audit Commands on `webapp` Server

When connected to the `webapp` terminal via SSH, run these commands to instantly inspect Kong's live configuration:

#### Linux / macOS (Bash with `jq`):
```bash
# 1. Audit all Services
curl -s http://localhost:8001/services | jq -r '.data[] | "[\(.name)] -> http://\(.host):\(.port)\(.path)"'

# 2. Audit all 21 Routes (Name, Paths & Service ID)
curl -s http://localhost:8001/routes | jq -r '.data[] | "Route: \(.name) | Paths: \(.paths | join(", "))"'

# 3. Check SICC Routes specifically
curl -s http://localhost:8001/services/imops-sicc-incident-service/routes | jq -r '.data[] | "Route: \(.name) | Paths: \(.paths | join(", "))"'

# 4. Check Consumer & Credentials
curl -s http://localhost:8001/consumers | jq -r '.data[] | "Consumer: \(.username) (ID: \(.id))"'
curl -s http://localhost:8001/consumers/va_system_consumer/basic-auth | jq .

# 5. Check Service-Level Plugins (basic-auth, rate-limiting, acl)
curl -s http://localhost:8001/services/imops-sicc-incident-service/plugins | jq -r '.data[] | "Plugin: \(.name) (Enabled: \(.enabled))"'

# 6. Check Route-Level Translator Plugins (post-function)
curl -s http://localhost:8001/routes/va-sov-38alt-l4-icc-1-crowding/plugins | jq .
```

#### Windows (PowerShell):
```powershell
# Check all Routes (Name, Paths & Service ID)
(curl.exe -s http://localhost:8001/routes | ConvertFrom-Json).data | ForEach-Object { "Route: $($_.name) | Paths: $($_.paths -join ', ') | Service ID: $($_.service.id)" }

# Check Consumer & Credentials
(curl.exe -s http://localhost:8001/consumers | ConvertFrom-Json).data | ForEach-Object { "Consumer: $($_.username) (ID: $($_.id))" }
(curl.exe -s http://localhost:8001/consumers/va_system_consumer/basic-auth | ConvertFrom-Json).data | ForEach-Object { "User: $($_.username) | ID: $($_.id)" }

# Check Service Plugins
(curl.exe -s http://localhost:8001/services/imops-sicc-incident-service/plugins | ConvertFrom-Json).data | ForEach-Object { "Plugin: $($_.name) (Enabled: $($_.enabled))" }
```

---

### 9.11 Accessing Kong Manager from Remote Workstation (`vg`)

If accessing the Kong Manager UI from another machine (e.g. the `vg` appliance at `http://<WEBAPP_IP>:8002`), ensure `KONG_ADMIN_GUI_API_URL` in `docker-compose.yml` points to the `webapp` IP rather than `localhost`:

```yaml
KONG_ADMIN_GUI_URL: http://<WEBAPP_IP>:8002
KONG_ADMIN_GUI_API_URL: http://<WEBAPP_IP>:8001
```

*Reason:* Kong Manager is a client-side browser SPA. Setting this allows the browser on `vg` to query the `webapp` host on port `8001` rather than trying to query `localhost` on the `vg` machine itself.

---

## 10. Future Roadmap & Observability

The detailed architectural roadmap and enterprise-grade observability specifications have been extracted into a dedicated document:

👉 **[Kong_Gateway_Future_Roadmap.md](file:///c:/Projects/cde/apigw/docs/Kong_Gateway_Future_Roadmap.md)**

### Key Roadmap Areas Covered in the Dedicated Document:
1. **Visual Request & Response Audit Trail:**
   * Streaming telemetry to n8n webhook (`c:\Projects\cde\n8n`) into PostgreSQL & MinIO Lakehouse.
   * Full request/response payload body logging.
   * Real-time web-based log viewer (Dozzle) on port `8888`.
2. **Upstream Resilience & Health Checks:** Active/passive circuit breaking for iMOPS backend.
3. **Declarative Configuration & GitOps (decK):** Version-controlling all gateway objects in Git.
4. **Security Hardening:** HTTPS/TLS on port `8443` and CCTV VLAN subnet isolation.
5. **Telemetry & Dashboards:** Prometheus metrics scraping and Grafana dashboard alerts.
