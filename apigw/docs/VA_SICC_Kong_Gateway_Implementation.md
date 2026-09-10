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
1. **Crowding VA:** `CROWDING_VA-SOV_38ALT_L4_ICC_1`
2. **Loitering VA:** `LOITERING_VA-SOV_38ALT_L4_Lift_Lobby`

---

## 2. Architecture & Request Flow

```mermaid
sequenceDiagram
    autonumber
    participant VA as VA Camera / Engine
    participant Kong as Kong Gateway (Port 8088/8443)
    participant Monitor as iMOPS Monitor (http://<BACKEND_HOST_IP>:13000/api/incidents/monitor)

    VA->>Kong: GET or POST /va/sov-38alt-crowding (Basic Auth)
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
* **External Public Route:** `GET` or `POST` `http://<KONG_IP>:8088/va/sov-38alt-crowding`
* **Destination Upstream:** `POST http://host.docker.internal:13000/api/incidents/monitor`
* **Headers to Upstream:**
  ```http
  Authorization: Basic <Base64(username:password)>
  Content-Type: application/json
  ```
* **Generated JSON Payload:**
  ```json
  {
    "site": "SICC",
    "deviceName": "CROWDING_VA-SOV_38ALT_L4_ICC_1",
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
* **External Public Route:** `GET` or `POST` `http://<KONG_IP>:8088/va/sov-38alt-loitering`
* **Destination Upstream:** `POST http://host.docker.internal:13000/api/incidents/monitor`
* **Headers to Upstream:**
  ```http
  Authorization: Basic <Base64(username:password)>
  Content-Type: application/json
  ```
* **Generated JSON Payload:**
  ```json
  {
    "site": "SOV",
    "deviceName": "LOITERING_VA-SOV_38ALT_L4_Lift_Lobby",
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

## 5. Step-by-Step Kong Gateway Configuration

You can configure Kong either using the **Command Line (`curl`)** or visually via **Kong Manager UI** (`http://localhost:8002`).

### Approach A: Command Line (Windows & Linux)

#### Step 0 (Optional): Delete All Existing Kong Objects (Clean Reset)
If you ever want to wipe all plugins, routes, services, and consumers to start fresh:

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
  -d "name=imops-incident-monitor-service" `
  -d "url=http://host.docker.internal:13000/api/incidents/monitor"
```

**Linux / macOS (Bash):**
```bash
curl -i -X POST http://localhost:8001/services \
  -d "name=imops-incident-monitor-service" \
  -d "url=http://host.docker.internal:13000/api/incidents/monitor"
```

---

#### Step 2: Configure Authorization & Throttling on the Service

##### 2.1 Enable `basic-auth` Plugin (Perimeter Authorizer & Pass-Through):
Setting `config.hide_credentials=false` ensures the `Authorization: Basic ...` header is passed directly to the backend.

```powershell
# Windows PowerShell
curl.exe -i -X POST http://localhost:8001/services/imops-incident-monitor-service/plugins `
  -d "name=basic-auth" `
  -d "config.hide_credentials=false"
```
```bash
# Linux / macOS Bash
curl -i -X POST http://localhost:8001/services/imops-incident-monitor-service/plugins \
  -d "name=basic-auth" \
  -d "config.hide_credentials=false"
```

##### 2.2 Enable `rate-limiting` Plugin (Throttler):
```powershell
# Windows PowerShell
curl.exe -i -X POST http://localhost:8001/services/imops-incident-monitor-service/plugins `
  -d "name=rate-limiting" `
  -d "config.minute=60" `
  -d "config.policy=local"
```
```bash
# Linux / macOS Bash
curl -i -X POST http://localhost:8001/services/imops-incident-monitor-service/plugins \
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
curl.exe -i -X POST http://localhost:8001/services/imops-incident-monitor-service/routes `
  -d "name=va-crowding-sov-38alt" `
  -d "paths[]=/va/sov-38alt-crowding" `
  -d "methods[]=GET" `
  -d "methods[]=POST" `
  -d "strip_path=true"
```
```bash
# Linux / macOS Bash
curl -i -X POST http://localhost:8001/services/imops-incident-monitor-service/routes \
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
local b = string.format('{"site":"SOV","deviceName":"CROWDING_VA-SOV_38ALT_L4_ICC_1","incidentType":"CROWDING","timestamp":%d,"mode":"incident","metadata":{"source":"vizzio_va","webhook":"crowding_sov_38alt_l4_icc_1","associatedCamera":"SOV 38ALT L4 ICC 1"}}', now)
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
  --data-urlencode "config.access[]=local now = os.time(); kong.service.request.set_method('POST'); kong.service.request.set_header('Authorization', 'Basic dml6emlvQGltb3BzLmxvY2FsOnhBSkhra203bTNWNU1odEYweEdN'); kong.service.request.set_header('Content-Type', 'application/json'); local b = string.format('{\"site\":\"SOV\",\"deviceName\":\"CROWDING_VA-SOV_38ALT_L4_ICC_1\",\"incidentType\":\"CROWDING\",\"timestamp\":%d,\"mode\":\"incident\",\"metadata\":{\"source\":\"vizzio_va\",\"webhook\":\"crowding_sov_38alt_l4_icc_1\",\"associatedCamera\":\"SOV 38ALT L4 ICC 1\"}}', now); kong.service.request.set_raw_body(b);"
```

---

#### Step 4: Configure Route 2 — Loitering VA

##### 4.1 Create Public Route:
```powershell
# Windows PowerShell
curl.exe -i -X POST http://localhost:8001/services/imops-incident-monitor-service/routes `
  -d "name=va-loitering-sov-38alt" `
  -d "paths[]=/va/sov-38alt-loitering" `
  -d "methods[]=GET" `
  -d "methods[]=POST" `
  -d "strip_path=true"
```
```bash
# Linux / macOS Bash
curl -i -X POST http://localhost:8001/services/imops-incident-monitor-service/routes \
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
local b = string.format('{"site":"SOV","deviceName":"LOITERING_VA-SOV_38ALT_L4_Lift_Lobby","incidentType":"LOITERING","timestamp":%d,"mode":"incident","metadata":{"source":"vizzio_va","webhook":"loitering_sov_38alt_l4_lift_lobby","associatedCamera":"SOV 38ALT L4 Lift Lobby"}}', now)
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
  --data-urlencode "config.access[]=local now = os.time(); kong.service.request.set_method('POST'); kong.service.request.set_header('Authorization', 'Basic dml6emlvQGltb3BzLmxvY2FsOnhBSkhra203bTNWNU1odEYweEdN'); kong.service.request.set_header('Content-Type', 'application/json'); local b = string.format('{\"site\":\"SOV\",\"deviceName\":\"LOITERING_VA-SOV_38ALT_L4_Lift_Lobby\",\"incidentType\":\"LOITERING\",\"timestamp\":%d,\"mode\":\"incident\",\"metadata\":{\"source\":\"vizzio_va\",\"webhook\":\"loitering_sov_38alt_l4_lift_lobby\",\"associatedCamera\":\"SOV 38ALT L4 Lift Lobby\"}}', now); kong.service.request.set_raw_body(b);"
```

---

### Approach B: Kong Manager UI (`http://localhost:8002`)

1. **Create Gateway Service:**
   - Go to **Gateway Services** -> Click **New Gateway Service**.
   - **Name:** `imops-incident-monitor-service`
   - **Upstream URL:** `http://host.docker.internal:13000/api/incidents/monitor`
   - Click **Save**.

2. **Add Security & Throttling Plugins:**
   - Under `imops-incident-monitor-service` -> **Plugins** -> **Add Plugin** -> Select **Basic Auth**.
   - Set **Hide Credentials** to `false` (so iMOPS receives the Basic Auth header). Click **Save**.
   - Click **Add Plugin** again -> Select **Rate Limiting**.
   - Set **Config.Minute** to `60`. Click **Save**.

3. **Add Consumer & Credentials:**
   - Go to **Consumers** -> **New Consumer** -> Username: `va_system_consumer`. Click **Save**.
   - Open `va_system_consumer` -> **Credentials** tab -> **Basic Auth** -> **New Basic Auth Credential**.
   - Enter **Username:** `vizzio@imops.local` and **Password:** `xAJHkkm7m3V5MhtF0xGM`. Click **Save**.

4. **Add Crowding Route:**
   - Under `imops-incident-monitor-service` -> **Routes** -> **New Route**.
   - **Name:** `va-crowding-sov-38alt` | **Paths:** `/va/sov-38alt-crowding` | Check **GET** and **POST**.
   - **Strip Path:** Enable (`true`). Click **Save**.
   - Open this route -> **Plugins** -> **Add Plugin** -> Select **Pre-Function**.
   - In **Config.Access**, paste this exact snippet:
     ```lua
     local now = os.time()
     kong.service.request.set_method("POST")
     kong.service.request.set_header("Authorization", "Basic dml6emlvQGltb3BzLmxvY2FsOnhBSkhra203bTNWNU1odEYweEdN")
     kong.service.request.set_header("Content-Type", "application/json")
     local b = string.format('{"site":"SOV","deviceName":"CROWDING_VA-SOV_38ALT_L4_ICC_1","incidentType":"CROWDING","timestamp":%d,"mode":"incident","metadata":{"source":"vizzio_va","webhook":"crowding_sov_38alt_l4_icc_1","associatedCamera":"SOV 38ALT L4 ICC 1"}}', now)
     kong.service.request.set_raw_body(b)
     ```
   - Click **Save**.

5. **Add Loitering Route:**
   - Under `imops-incident-monitor-service` -> **Routes** -> **New Route**.
   - **Name:** `va-loitering-sov-38alt` | **Paths:** `/va/sov-38alt-loitering` | Check **GET** and **POST**.
   - **Strip Path:** Enable (`true`). Click **Save**.
   - Open this route -> **Plugins** -> **Add Plugin** -> Select **Pre-Function**.
   - In **Config.Access**, paste this exact snippet:
     ```lua
     local now = os.time()
     kong.service.request.set_method("POST")
     kong.service.request.set_header("Authorization", "Basic dml6emlvQGltb3BzLmxvY2FsOnhBSkhra203bTNWNU1odEYweEdN")
     kong.service.request.set_header("Content-Type", "application/json")
     local b = string.format('{"site":"SOV","deviceName":"LOITERING_VA-SOV_38ALT_L4_Lift_Lobby","incidentType":"LOITERING","timestamp":%d,"mode":"incident","metadata":{"source":"vizzio_va","webhook":"loitering_sov_38alt_l4_lift_lobby","associatedCamera":"SOV 38ALT L4 Lift Lobby"}}', now)
     kong.service.request.set_raw_body(b)
     ```
   - Click **Save**.

---

## 6. How to Add More VAs in the Future (No Backend Code Changes)

When a 3rd or 4th camera comes along (e.g. `INTRUSION_VA-SOV_38ALT_Roof`):
**You do NOT modify iMOPS.** You simply register the new Route and its JSON payload in Kong:

### Windows (PowerShell):
```powershell
# 1. Create Route
curl.exe -i -X POST http://localhost:8001/services/imops-incident-monitor-service/routes `
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
curl -i -X POST http://localhost:8001/services/imops-incident-monitor-service/routes \
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

## 7. How to Update or Rotate Consumer Credentials

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

## 8. Verification & Testing

Verify both `GET` and `POST` triggers through Kong on port `8088`:

### 1. Test Crowding VA
```powershell
# Windows (GET or POST)
curl.exe -i -X GET http://localhost:8088/va/sov-38alt-crowding -u "vizzio@imops.local:xAJHkkm7m3V5MhtF0xGM"
curl.exe -i -X POST http://localhost:8088/va/sov-38alt-crowding -u "vizzio@imops.local:xAJHkkm7m3V5MhtF0xGM"
```
```bash
# Linux / macOS (GET or POST)
curl -i -X GET http://localhost:8088/va/sov-38alt-crowding -u "vizzio@imops.local:xAJHkkm7m3V5MhtF0xGM"
curl -i -X POST http://localhost:8088/va/sov-38alt-crowding -u "vizzio@imops.local:xAJHkkm7m3V5MhtF0xGM"
```

### 2. Test Loitering VA
```powershell
# Windows (GET or POST)
curl.exe -i -X GET http://localhost:8088/va/sov-38alt-loitering -u "vizzio@imops.local:xAJHkkm7m3V5MhtF0xGM"
curl.exe -i -X POST http://localhost:8088/va/sov-38alt-loitering -u "vizzio@imops.local:xAJHkkm7m3V5MhtF0xGM"
```
```bash
# Linux / macOS (GET or POST)
curl -i -X GET http://localhost:8088/va/sov-38alt-loitering -u "vizzio@imops.local:xAJHkkm7m3V5MhtF0xGM"
curl -i -X POST http://localhost:8088/va/sov-38alt-loitering -u "vizzio@imops.local:xAJHkkm7m3V5MhtF0xGM"
```

### 3. Verify Rate Limiting / Throttling (Burst Protection)
```powershell
1..65 | ForEach-Object { curl.exe -s -o /dev/null -w "%{http_code}\n" http://localhost:8088/va/sov-38alt-crowding -u "vizzio@imops.local:xAJHkkm7m3V5MhtF0xGM" }
```
Requests 1–60 return `200 OK`. Request 61+ returns **`HTTP 429 Too Many Requests`**.

### 4. How to Adjust or Customize Rate Limits

By default, Kong Gateway enforces **60 requests per minute**. You can change this limit at any time with **zero downtime** and **no container restarts**.

#### Via Kong Manager UI (`http://localhost:8002`) (Recommended):
1. Open **[http://localhost:8002](http://localhost:8002)**.
2. Go to **Gateway Services** ➔ click **`imops-incident-monitor-service`**.
3. Go to the **Plugins** tab.
4. Locate **`rate-limiting`** ➔ click the action menu (**`...`**) on the right ➔ click **Edit**.
5. Change **`Minute`** to your desired limit (e.g. `120`, `300`).
6. *(Optional)* Add a **`Second`** burst cap (e.g. `5` req/sec).
7. Click **Save Changes** (takes effect immediately).

#### Via Command Line (`curl`):
```powershell
# Retrieve plugin ID:
$pluginId = (Invoke-RestMethod http://localhost:8001/services/imops-incident-monitor-service/plugins).data | 
    Where-Object { $_.name -eq "rate-limiting" } | 
    Select-Object -ExpandProperty id

# Update to 120 requests/minute:
curl.exe -i -X PATCH "http://localhost:8001/plugins/$pluginId" -d "config.minute=120"
```

### Expected Success Response:
```json
{
  "success": true,
  "action": "created",
  "incident": {
    "_id": "66e01a2b...",
    "title": "CROWDING: CROWDING_VA-SOV_38ALT_L4_ICC_1",
    "status": "new",
    "priority": "medium",
    "site": "SOV",
    "source": {
      "deviceName": "CROWDING_VA-SOV_38ALT_L4_ICC_1"
    }
  }
}
```

---

## 9. Future Roadmap & Observability

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
