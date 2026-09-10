# Kong Gateway - Project DORS Video Analytics (VA) Ingress Implementation Guide

This guide details the complete architecture, configuration scripts, and step-by-step instructions for implementing **Project DORS Video Analytics (VA) Ingress** using **Kong Gateway OSS 3.9**.

Kong Gateway sits at the perimeter as the **Authorizer, Throttler, and Translator**, forwarding triggers directly to the downstream iMOPS backend at:
`http://<BACKEND_HOST_IP>:13000/api/incidents/monitor` *(Host port 13000 maps to container port 3000)*.

---

## 1. Architectural Decision: Same vs. Dedicated Gateway Service?

> [!IMPORTANT]
> **Question:** *Should we use the same Gateway Service as SOV or a different one?*  
> **Answer: Use a DEDICATED Gateway Service (`imops-dors-incident-service`).**

### Comparison & Justification:

| Architectural Metric | Option A: Dedicated Service (`imops-dors-incident-service`) **(Implemented)** | Option B: Shared Service with SOV |
| :--- | :--- | :--- |
| **Site Isolation & Security** | **Strictly Isolated (via ACL).** DORS credentials cannot trigger SOV cameras, and SOV credentials cannot trigger DORS cameras. Attempting cross-site access returns `403 Forbidden`. | **Permissive.** Any consumer with basic-auth could call any route attached to the service unless complex route-level policies are configured. |
| **Credentials & Upstream Auth** | Upstream receives DORS's specific Basic Auth (`dors_user@isems.com`). | Risk of auth header mismatch or collision. |
| **Observability & Metrics** | Separate metrics, logs, and Grafana graphs specifically for DORS. | DORS and SOV traffic are blended together in service-level telemetry. |
| **Throttling & Rate Limits** | Independent rate limits (e.g. DORS can have 60, 120, or 300 req/min without impacting SOV). | Shared global rate limit pool. |
| **Network Whitelisting** | Can attach `ip-restriction` plugin dedicated to the DORS CCTV VLAN subnet. | CCTV subnets from different physical sites must be combined. |
| **Gateway Performance** | Zero overhead. Services in Kong are lightweight routing records. | Zero overhead. |

---

## 2. Credentials & Target Endpoints

### 2.1 Credentials

| Field | Value |
| :--- | :--- |
| **Username** | `dors_user@isems.com` |
| **Password** | `1Pu1znaPbTqXcyC5KVpP` |
| **Base64 HTTP Header** | `Authorization: Basic ZG9yc191c2VyQGlzZW1zLmNvbToxUHUxem5hUGJUcVhjeUM1S1ZwUA==` |
| **ACL Group** | `dors_group` |

### 2.2 The 4 DORS Video Analytics (VA) Endpoints

Each route on Kong supports **both** clean paths (`/va/...`) and the legacy translate paths (`/api/incidents/translate/...`) so any camera firmware configuration works seamlessly:

| # | VA Webhook / Device | Primary Path | Legacy Path Alias | Incident Type |
| :- | :--- | :--- | :--- | :--- |
| **1** | `dors_dop_c02_cyclist` | `/va/dors-dop-c02-cyclist` | `/api/incidents/translate/vizzio/va/dors_dop_c02_cyclist` | `CYCLIST_GATHERING` |
| **2** | `dors_waiting_c03_cyclist` | `/va/dors-waiting-c03-cyclist` | `/api/incidents/translate/vizzio/va/dors_waiting_c03_cyclist` | `CYCLIST_GATHERING` |
| **3** | `dors_dop_c01_illegal` | `/va/dors-dop-c01-illegal` | `/api/incidents/translate/vizzio/va/dors_dop_c01_illegal` | `ILLEGAL_PARKING` |
| **4** | `dors_dop_c02_illegal` | `/va/dors-dop-c02-illegal` | `/api/incidents/translate/vizzio/va/dors_dop_c02_illegal` | `ILLEGAL_PARKING` |

---

## 3. End-to-End Sequence Diagram

```mermaid
sequenceDiagram
    autonumber
    participant Cam as DORS Camera / Edge VA
    participant Kong as Kong Gateway (Port 8088)
    participant iMOPS as iMOPS Backend (:13000/api/incidents/monitor)

    Cam->>Kong: GET or POST /va/dors-dop-c02-cyclist (dors_user@isems.com)
    Note over Kong: 1. basic-auth verifies credentials<br/>2. acl verifies consumer belongs to dors_group<br/>3. rate-limiting checks quota (60 req/min)<br/>4. post-function translates method to POST<br/>5. post-function sets Authorization: Basic ZG9yc1...<br/>6. post-function injects live timestamp & DORS incident JSON
    Kong->>iMOPS: POST /api/incidents/monitor (Basic Auth + JSON Payload)
    iMOPS-->>Kong: HTTP 200 OK (Incident Created)
    Kong-->>Cam: HTTP 200 OK
```

---

## 4. One-Click Automated Setup Scripts

Automated setup scripts are ready in `c:\Projects\cde\apigw\scripts\`:

### Windows (PowerShell):
Run in PowerShell:
```powershell
powershell -ExecutionPolicy Bypass -File c:\Projects\cde\apigw\scripts\setup_dors_va.ps1
```

### Linux / macOS (Bash):
Run in terminal:
```bash
bash c:/Projects/cde/apigw/scripts/setup_dors_va.sh
```

---

## 5. Step-by-Step Manual Setup Guide

If you prefer to configure manually via `curl` commands:

### Step 1: Create the Dedicated DORS Gateway Service
Points upstream traffic to the iMOPS Incident Monitor endpoint on port `13000`.

#### Windows (PowerShell):
```powershell
curl.exe -i -X POST http://localhost:8001/services `
  -d "name=imops-dors-incident-service" `
  -d "url=http://host.docker.internal:13000/api/incidents/monitor"
```
#### Linux / macOS (Bash):
```bash
curl -i -X POST http://localhost:8001/services \
  -d "name=imops-dors-incident-service" \
  -d "url=http://host.docker.internal:13000/api/incidents/monitor"
```

---

### Step 2: Attach Service Plugins (Basic Auth, Rate Limiting, ACL)

#### Windows (PowerShell):
```powershell
# 1. Basic Auth Plugin
curl.exe -i -X POST http://localhost:8001/services/imops-dors-incident-service/plugins `
  -d "name=basic-auth" `
  -d "config.hide_credentials=false"

# 2. Rate Limiting Plugin (60 req/min)
curl.exe -i -X POST http://localhost:8001/services/imops-dors-incident-service/plugins `
  -d "name=rate-limiting" `
  -d "config.minute=60" `
  -d "config.policy=local"

# 3. ACL Plugin (Strict Site Isolation for dors_group)
curl.exe -i -X POST http://localhost:8001/services/imops-dors-incident-service/plugins `
  -d "name=acl" `
  -d "config.allow[]=dors_group"
```

#### Linux / macOS (Bash):
```bash
# 1. Basic Auth Plugin
curl -i -X POST http://localhost:8001/services/imops-dors-incident-service/plugins \
  -d "name=basic-auth" \
  -d "config.hide_credentials=false"

# 2. Rate Limiting Plugin (60 req/min)
curl -i -X POST http://localhost:8001/services/imops-dors-incident-service/plugins \
  -d "name=rate-limiting" \
  -d "config.minute=60" \
  -d "config.policy=local"

# 3. ACL Plugin (Strict Site Isolation for dors_group)
curl -i -X POST http://localhost:8001/services/imops-dors-incident-service/plugins \
  -d "name=acl" \
  -d "config.allow[]=dors_group"
```

---

### Step 3: Create DORS Consumer, Credentials & ACL Group

#### Windows (PowerShell):
```powershell
# 1. Create Consumer
curl.exe -i -X POST http://localhost:8001/consumers `
  -d "username=va_dors_consumer" `
  -d "custom_id=site_dors_va"

# 2. Add Basic Auth Credentials
curl.exe -i -X POST http://localhost:8001/consumers/va_dors_consumer/basic-auth `
  -d "username=dors_user@isems.com" `
  -d "password=1Pu1znaPbTqXcyC5KVpP"

# 3. Assign to ACL Group
curl.exe -i -X POST http://localhost:8001/consumers/va_dors_consumer/acls `
  -d "group=dors_group"
```

#### Linux / macOS (Bash):
```bash
# 1. Create Consumer
curl -i -X POST http://localhost:8001/consumers \
  -d "username=va_dors_consumer" \
  -d "custom_id=site_dors_va"

# 2. Add Basic Auth Credentials
curl -i -X POST http://localhost:8001/consumers/va_dors_consumer/basic-auth \
  -d "username=dors_user@isems.com" \
  -d "password=1Pu1znaPbTqXcyC5KVpP"

# 3. Assign to ACL Group
curl -i -X POST http://localhost:8001/consumers/va_dors_consumer/acls \
  -d "group=dors_group"
```

---

### Step 4: Create the 4 Routes and Attach Dynamic Translators

#### Route 1: Drop-Off Point C02 Cyclist Crowding (`va-dors-dop-c02-cyclist`)

##### Windows (PowerShell):
```powershell
curl.exe -i -X POST http://localhost:8001/services/imops-dors-incident-service/routes `
  -d "name=va-dors-dop-c02-cyclist" `
  -d "paths[]=/va/dors-dop-c02-cyclist" `
  -d "paths[]=/api/incidents/translate/vizzio/va/dors_dop_c02_cyclist" `
  -d "methods[]=GET" `
  -d "methods[]=POST" `
  -d "strip_path=true"

$lua1 = @'
local now = os.time()
kong.service.request.set_method("POST")
kong.service.request.set_header("Authorization", "Basic ZG9yc191c2VyQGlzZW1zLmNvbToxUHUxem5hUGJUcVhjeUM1S1ZwUA==")
kong.service.request.set_header("Content-Type", "application/json")
local b = string.format('{"site":"DORS","deviceName":"DORS Drop-Off Point C02 VA Cyclist Crowding","incidentType":"CYCLIST_GATHERING","timestamp":%d,"mode":"incident","metadata":{"source":"vizzio_va","webhook":"dors_dop_c02_cyclist","associatedCamera":"DORS Drop-Off Point C02"}}', now)
kong.service.request.set_raw_body(b)
'@

$body1 = @{
    name = "post-function"
    config = @{ access = @($lua1) }
} | ConvertTo-Json

Invoke-RestMethod -Uri "http://localhost:8001/routes/va-dors-dop-c02-cyclist/plugins" -Method Post -ContentType "application/json" -Body $body1
```

##### Linux / macOS (Bash):
```bash
curl -i -X POST http://localhost:8001/services/imops-dors-incident-service/routes \
  -d "name=va-dors-dop-c02-cyclist" \
  -d "paths[]=/va/dors-dop-c02-cyclist" \
  -d "paths[]=/api/incidents/translate/vizzio/va/dors_dop_c02_cyclist" \
  -d "methods[]=GET" \
  -d "methods[]=POST" \
  -d "strip_path=true"

curl -i -X POST http://localhost:8001/routes/va-dors-dop-c02-cyclist/plugins \
  -d "name=post-function" \
  --data-urlencode "config.access[]=local now = os.time(); kong.service.request.set_method('POST'); kong.service.request.set_header('Authorization', 'Basic ZG9yc191c2VyQGlzZW1zLmNvbToxUHUxem5hUGJUcVhjeUM1S1ZwUA=='); kong.service.request.set_header('Content-Type', 'application/json'); local b = string.format('{\"site\":\"DORS\",\"deviceName\":\"DORS Drop-Off Point C02 VA Cyclist Crowding\",\"incidentType\":\"CYCLIST_GATHERING\",\"timestamp\":%d,\"mode\":\"incident\",\"metadata\":{\"source\":\"vizzio_va\",\"webhook\":\"dors_dop_c02_cyclist\",\"associatedCamera\":\"DORS Drop-Off Point C02\"}}', now); kong.service.request.set_raw_body(b);"
```

---

#### Route 2: Waiting Area C03 Cyclist Crowding (`va-dors-waiting-c03-cyclist`)

##### Windows (PowerShell):
```powershell
curl.exe -i -X POST http://localhost:8001/services/imops-dors-incident-service/routes `
  -d "name=va-dors-waiting-c03-cyclist" `
  -d "paths[]=/va/dors-waiting-c03-cyclist" `
  -d "paths[]=/api/incidents/translate/vizzio/va/dors_waiting_c03_cyclist" `
  -d "methods[]=GET" `
  -d "methods[]=POST" `
  -d "strip_path=true"

$lua2 = @'
local now = os.time()
kong.service.request.set_method("POST")
kong.service.request.set_header("Authorization", "Basic ZG9yc191c2VyQGlzZW1zLmNvbToxUHUxem5hUGJUcVhjeUM1S1ZwUA==")
kong.service.request.set_header("Content-Type", "application/json")
local b = string.format('{"site":"DORS","deviceName":"DORS Waiting Area C03 VA Cyclist Crowding","incidentType":"CYCLIST_GATHERING","timestamp":%d,"mode":"incident","metadata":{"source":"vizzio_va","webhook":"dors_waiting_c03_cyclist","associatedCamera":"DORS Waiting Area C03"}}', now)
kong.service.request.set_raw_body(b)
'@

$body2 = @{
    name = "post-function"
    config = @{ access = @($lua2) }
} | ConvertTo-Json

Invoke-RestMethod -Uri "http://localhost:8001/routes/va-dors-waiting-c03-cyclist/plugins" -Method Post -ContentType "application/json" -Body $body2
```

##### Linux / macOS (Bash):
```bash
curl -i -X POST http://localhost:8001/services/imops-dors-incident-service/routes \
  -d "name=va-dors-waiting-c03-cyclist" \
  -d "paths[]=/va/dors-waiting-c03-cyclist" \
  -d "paths[]=/api/incidents/translate/vizzio/va/dors_waiting_c03_cyclist" \
  -d "methods[]=GET" \
  -d "methods[]=POST" \
  -d "strip_path=true"

curl -i -X POST http://localhost:8001/routes/va-dors-waiting-c03-cyclist/plugins \
  -d "name=post-function" \
  --data-urlencode "config.access[]=local now = os.time(); kong.service.request.set_method('POST'); kong.service.request.set_header('Authorization', 'Basic ZG9yc191c2VyQGlzZW1zLmNvbToxUHUxem5hUGJUcVhjeUM1S1ZwUA=='); kong.service.request.set_header('Content-Type', 'application/json'); local b = string.format('{\"site\":\"DORS\",\"deviceName\":\"DORS Waiting Area C03 VA Cyclist Crowding\",\"incidentType\":\"CYCLIST_GATHERING\",\"timestamp\":%d,\"mode\":\"incident\",\"metadata\":{\"source\":\"vizzio_va\",\"webhook\":\"dors_waiting_c03_cyclist\",\"associatedCamera\":\"DORS Waiting Area C03\"}}', now); kong.service.request.set_raw_body(b);"
```

---

#### Route 3: Drop-Off Point C01 Illegal Parking (`va-dors-dop-c01-illegal`)

##### Windows (PowerShell):
```powershell
curl.exe -i -X POST http://localhost:8001/services/imops-dors-incident-service/routes `
  -d "name=va-dors-dop-c01-illegal" `
  -d "paths[]=/va/dors-dop-c01-illegal" `
  -d "paths[]=/api/incidents/translate/vizzio/va/dors_dop_c01_illegal" `
  -d "methods[]=GET" `
  -d "methods[]=POST" `
  -d "strip_path=true"

$lua3 = @'
local now = os.time()
kong.service.request.set_method("POST")
kong.service.request.set_header("Authorization", "Basic ZG9yc191c2VyQGlzZW1zLmNvbToxUHUxem5hUGJUcVhjeUM1S1ZwUA==")
kong.service.request.set_header("Content-Type", "application/json")
local b = string.format('{"site":"DORS","deviceName":"DORS Drop-Off Point C01 VA Illegal Parking","incidentType":"ILLEGAL_PARKING","timestamp":%d,"mode":"incident","metadata":{"source":"vizzio_va","webhook":"dors_dop_c01_illegal","associatedCamera":"DORS Drop-Off Point C01"}}', now)
kong.service.request.set_raw_body(b)
'@

$body3 = @{
    name = "post-function"
    config = @{ access = @($lua3) }
} | ConvertTo-Json

Invoke-RestMethod -Uri "http://localhost:8001/routes/va-dors-dop-c01-illegal/plugins" -Method Post -ContentType "application/json" -Body $body3
```

##### Linux / macOS (Bash):
```bash
curl -i -X POST http://localhost:8001/services/imops-dors-incident-service/routes \
  -d "name=va-dors-dop-c01-illegal" \
  -d "paths[]=/va/dors-dop-c01-illegal" \
  -d "paths[]=/api/incidents/translate/vizzio/va/dors_dop_c01_illegal" \
  -d "methods[]=GET" \
  -d "methods[]=POST" \
  -d "strip_path=true"

curl -i -X POST http://localhost:8001/routes/va-dors-dop-c01-illegal/plugins \
  -d "name=post-function" \
  --data-urlencode "config.access[]=local now = os.time(); kong.service.request.set_method('POST'); kong.service.request.set_header('Authorization', 'Basic ZG9yc191c2VyQGlzZW1zLmNvbToxUHUxem5hUGJUcVhjeUM1S1ZwUA=='); kong.service.request.set_header('Content-Type', 'application/json'); local b = string.format('{\"site\":\"DORS\",\"deviceName\":\"DORS Drop-Off Point C01 VA Illegal Parking\",\"incidentType\":\"ILLEGAL_PARKING\",\"timestamp\":%d,\"mode\":\"incident\",\"metadata\":{\"source\":\"vizzio_va\",\"webhook\":\"dors_dop_c01_illegal\",\"associatedCamera\":\"DORS Drop-Off Point C01\"}}', now); kong.service.request.set_raw_body(b);"
```

---

#### Route 4: Drop-Off Point C02 Illegal Parking (`va-dors-dop-c02-illegal`)

##### Windows (PowerShell):
```powershell
curl.exe -i -X POST http://localhost:8001/services/imops-dors-incident-service/routes `
  -d "name=va-dors-dop-c02-illegal" `
  -d "paths[]=/va/dors-dop-c02-illegal" `
  -d "paths[]=/api/incidents/translate/vizzio/va/dors_dop_c02_illegal" `
  -d "methods[]=GET" `
  -d "methods[]=POST" `
  -d "strip_path=true"

$lua4 = @'
local now = os.time()
kong.service.request.set_method("POST")
kong.service.request.set_header("Authorization", "Basic ZG9yc191c2VyQGlzZW1zLmNvbToxUHUxem5hUGJUcVhjeUM1S1ZwUA==")
kong.service.request.set_header("Content-Type", "application/json")
local b = string.format('{"site":"DORS","deviceName":"DORS Drop-Off Point C02 VA Illegal Parking","incidentType":"ILLEGAL_PARKING","timestamp":%d,"mode":"incident","metadata":{"source":"vizzio_va","webhook":"dors_dop_c02_illegal","associatedCamera":"DORS Drop-Off Point C02"}}', now)
kong.service.request.set_raw_body(b)
'@

$body4 = @{
    name = "post-function"
    config = @{ access = @($lua4) }
} | ConvertTo-Json

Invoke-RestMethod -Uri "http://localhost:8001/routes/va-dors-dop-c02-illegal/plugins" -Method Post -ContentType "application/json" -Body $body4
```

##### Linux / macOS (Bash):
```bash
curl -i -X POST http://localhost:8001/services/imops-dors-incident-service/routes \
  -d "name=va-dors-dop-c02-illegal" \
  -d "paths[]=/va/dors-dop-c02-illegal" \
  -d "paths[]=/api/incidents/translate/vizzio/va/dors_dop_c02_illegal" \
  -d "methods[]=GET" \
  -d "methods[]=POST" \
  -d "strip_path=true"

curl -i -X POST http://localhost:8001/routes/va-dors-dop-c02-illegal/plugins \
  -d "name=post-function" \
  --data-urlencode "config.access[]=local now = os.time(); kong.service.request.set_method('POST'); kong.service.request.set_header('Authorization', 'Basic ZG9yc191c2VyQGlzZW1zLmNvbToxUHUxem5hUGJUcVhjeUM1S1ZwUA=='); kong.service.request.set_header('Content-Type', 'application/json'); local b = string.format('{\"site\":\"DORS\",\"deviceName\":\"DORS Drop-Off Point C02 VA Illegal Parking\",\"incidentType\":\"ILLEGAL_PARKING\",\"timestamp\":%d,\"mode\":\"incident\",\"metadata\":{\"source\":\"vizzio_va\",\"webhook\":\"dors_dop_c02_illegal\",\"associatedCamera\":\"DORS Drop-Off Point C02\"}}', now); kong.service.request.set_raw_body(b);"
```

---

## 6. Kong Manager UI Visual Instructions (`http://localhost:8002`)

If configuring through the web browser:

1. Open **[http://localhost:8002](http://localhost:8002)**.
2. **Gateway Services:**
   * Click **New Gateway Service**.
   * Name: `imops-dors-incident-service`.
   * Upstream URL: `http://host.docker.internal:13000/api/incidents/monitor`.
   * Click **Save**.
3. **Attach Service Plugins:**
   * Go to the **Plugins** tab of `imops-dors-incident-service`.
   * Add **Basic Auth** (`hide_credentials = false`).
   * Add **Rate Limiting** (`minute = 60`).
   * Add **ACL** (`allow = dors_group`).
4. **Consumers:**
   * Click **Consumers** ➔ **New Consumer**.
   * Username: `va_dors_consumer`.
   * Custom ID: `site_dors_va`.
   * Go to **Credentials** ➔ Add **Basic Auth** (`dors_user@isems.com` / `1Pu1znaPbTqXcyC5KVpP`).
   * Go to **Groups** ➔ Add to group `dors_group`.
5. **Routes:**
   * Click **Routes** ➔ **New Route**.
   * Service: select `imops-dors-incident-service`.
   * Paths: `/va/dors-dop-c02-cyclist` and `/api/incidents/translate/vizzio/va/dors_dop_c02_cyclist`.
   * Methods: `GET` and `POST`.
   * Strip Path: `Yes (true)`.
   * Repeat for the other 3 routes.
6. **Attach Post-Function Translators:**
   * Go to each Route ➔ **Plugins** tab ➔ **Add Plugin** ➔ **Post-Function**.
   * In the `access` field, paste the corresponding Lua script from Section 5.
   * Click **Save**.

---

## 7. Verification & Testing

### 7.1 Test All 4 DORS Endpoints (Valid Credentials)

```powershell
# 1. DOP C02 Cyclist
curl.exe -i -X GET http://localhost:8088/va/dors-dop-c02-cyclist -u "dors_user@isems.com:1Pu1znaPbTqXcyC5KVpP"

# 2. Waiting Area C03 Cyclist
curl.exe -i -X GET http://localhost:8088/va/dors-waiting-c03-cyclist -u "dors_user@isems.com:1Pu1znaPbTqXcyC5KVpP"

# 3. DOP C01 Illegal Parking
curl.exe -i -X GET http://localhost:8088/va/dors-dop-c01-illegal -u "dors_user@isems.com:1Pu1znaPbTqXcyC5KVpP"

# 4. DOP C02 Illegal Parking
curl.exe -i -X GET http://localhost:8088/va/dors-dop-c02-illegal -u "dors_user@isems.com:1Pu1znaPbTqXcyC5KVpP"
```

### 7.2 Negative Test 1: Invalid Password (Returns 401 Unauthorized)
```powershell
curl.exe -i -X GET http://localhost:8088/va/dors-dop-c02-cyclist -u "dors_user@isems.com:WRONG_PASSWORD"
```
**Expected Response:**
```http
HTTP/1.1 401 Unauthorized
WWW-Authenticate: Basic realm="service"

{"message":"Unauthorized","request_id":"..."}
```

### 7.3 Negative Test 2: Cross-Site Isolation (Returns 403 Forbidden)
Attempting to invoke a DORS route using the SOV credentials (`vizzio@imops.local`):
```powershell
curl.exe -i -X GET http://localhost:8088/va/dors-dop-c02-cyclist -u "vizzio@imops.local:xAJHkkm7m3V5MhtF0xGM"
```
**Expected Response:**
```http
HTTP/1.1 403 Forbidden

{"message":"You cannot consume this service","request_id":"..."}
```

### 7.4 Rate Limiting Burst Test (Returns 429 Too Many Requests)
```powershell
1..65 | ForEach-Object { curl.exe -s -o /dev/null -w "%{http_code}\n" http://localhost:8088/va/dors-dop-c02-cyclist -u "dors_user@isems.com:1Pu1znaPbTqXcyC5KVpP" }
```
Requests 1–60 return `200`. Request 61+ returns **`429 Too Many Requests`**.

---

## 8. How to Adjust or Customize Rate Limits

By default, Kong Gateway enforces **60 requests per minute** per consumer. You can change this limit at any time with **zero downtime** and **no container restarts**.

### Option A: Via Kong Manager UI (`http://localhost:8002`) (Recommended)

1. Open **[http://localhost:8002](http://localhost:8002)** in your browser.
2. Click **Gateway Services** in the left sidebar menu.
3. Click on **`imops-dors-incident-service`**.
4. Click on the **Plugins** tab across the top.
5. In the plugins table, locate **`rate-limiting`**:
   * Click the action menu (**`...`**) on the right side of the row (or click the plugin name).
   * Click **Edit**.
6. Under the **Config** section:
   * Modify **`Minute`**: Change `60` to your desired threshold (e.g. `120`, `300`).
   * *(Optional)* Set **`Second`**: Add a burst limit (e.g. `5` requests/second).
   * *(Optional)* Set **`Hour`** or **`Day`** for long-term quotas.
7. Click **Save** at the bottom right. The new limit takes effect immediately!

---

### Option B: Via Command Line (`curl` / PowerShell)

#### Windows (PowerShell):
```powershell
# 1. Retrieve the Rate Limiting Plugin ID on DORS Service:
$pluginId = (Invoke-RestMethod http://localhost:8001/services/imops-dors-incident-service/plugins).data | 
    Where-Object { $_.name -eq "rate-limiting" } | 
    Select-Object -ExpandProperty id

# 2. Update to 120 requests/minute:
curl.exe -i -X PATCH "http://localhost:8001/plugins/$pluginId" `
  -d "config.minute=120"
```

#### Linux / macOS (Bash):
```bash
# 1. Retrieve the Plugin ID:
PLUGIN_ID=$(curl -s http://localhost:8001/services/imops-dors-incident-service/plugins | \
  grep -o '"id":"[^"]*"' | head -n 1 | cut -d'"' -f4)

# 2. Update to 120 requests/minute:
curl -i -X PATCH "http://localhost:8001/plugins/$PLUGIN_ID" \
  -d "config.minute=120"
```

---

## 9. How to Rotate or Update Username and Password

In Kong Gateway, credentials belong to **Consumers** (e.g. `va_dors_consumer`). Because passwords are cryptographically hashed for security, updating a password is done by deleting the old credential and adding the new one.

### Option A: Via Kong Manager UI (`http://localhost:8002`) (Recommended)

#### 1. Update Ingress Consumer Credentials:
1. Open **[http://localhost:8002](http://localhost:8002)** in your browser.
2. Click **Consumers** in the left sidebar menu.
3. Click on **`va_dors_consumer`**.
4. Click on the **Credentials** tab (or **Basic Auth** sub-tab).
5. On the row showing the existing credential (`dors_user@isems.com`), click the **Action menu (`...`)** on the right ➔ click **Delete** (confirm delete).
6. Click **New Basic Auth Credential** (or **+ New Credential**).
7. Enter the new **Username** and new **Password**.
8. Click **Save**.

#### 2. Update Upstream Authorization Header (If iMOPS Backend Password Changed):
If the password was changed on the downstream iMOPS backend (`/api/incidents/monitor`) as well:
1. Calculate the new Base64 string in PowerShell:
   ```powershell
   [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("new_username:new_password"))
   ```
2. In Kong Manager, go to **Routes** (or under `imops-dors-incident-service` ➔ **Routes** tab).
3. Click on each of the 4 DORS routes ➔ go to the **Plugins** tab.
4. Click **`post-function`** ➔ click **Edit**.
5. In the Lua code, replace the Base64 string on line 4:
   ```lua
   kong.service.request.set_header("Authorization", "Basic <YOUR_NEW_BASE64>")
   ```
6. Click **Save**.

---

### Option B: Via Command Line (`curl` / PowerShell)

#### Windows (PowerShell):
```powershell
# 1. Find the existing credential ID:
$credId = (Invoke-RestMethod http://localhost:8001/consumers/va_dors_consumer/basic-auth).data[0].id

# 2. Delete the old credential:
curl.exe -i -X DELETE "http://localhost:8001/consumers/va_dors_consumer/basic-auth/$credId"

# 3. Create the new credential:
curl.exe -i -X POST "http://localhost:8001/consumers/va_dors_consumer/basic-auth" `
  -d "username=new_user@isems.com" `
  -d "password=NEW_PASSWORD_HERE"
```

#### Linux / macOS (Bash):
```bash
# 1. Find the existing credential ID:
CRED_ID=$(curl -s http://localhost:8001/consumers/va_dors_consumer/basic-auth | grep -o '"id":"[^"]*"' | head -n 1 | cut -d'"' -f4)

# 2. Delete the old credential:
curl -i -X DELETE "http://localhost:8001/consumers/va_dors_consumer/basic-auth/$CRED_ID"

# 3. Create the new credential:
curl -i -X POST "http://localhost:8001/consumers/va_dors_consumer/basic-auth" \
  -d "username=new_user@isems.com" \
  -d "password=NEW_PASSWORD_HERE"
```

---

## 10. Teardown / Clean-up One-Liner

If you ever need to completely remove the DORS Gateway Service, Routes, and Consumers:

### Windows (PowerShell):
```powershell
# Delete Service (automatically removes attached routes and service plugins)
curl.exe -i -X DELETE http://localhost:8001/services/imops-dors-incident-service

# Delete Consumer
curl.exe -i -X DELETE http://localhost:8001/consumers/va_dors_consumer
```

### Linux / macOS (Bash):
```bash
curl -i -X DELETE http://localhost:8001/services/imops-dors-incident-service
curl -i -X DELETE http://localhost:8001/consumers/va_dors_consumer
```

---

## 11. CLI Verification on `webapp` & Remote Browser Access

### 11.1 Command-Line Verification Commands (on `webapp` Linux VM)

#### Linux / macOS (Bash with `jq`):
```bash
# 1. Verify DORS Service
curl -s http://localhost:8001/services/imops-dors-incident-service | jq -r '"Service: \(.name) -> Target: http://\(.host):\(.port)\(.path)"'

# 2. Check all Routes (Name, Paths & Service ID)
curl -s http://localhost:8001/routes | jq -r '.data[] | "Route: \(.name) | Paths: \(.paths | join(", ")) | Service ID: \(.service.id)"'

# 3. Verify all 4 DORS Routes specifically
curl -s http://localhost:8001/services/imops-dors-incident-service/routes | jq -r '.data[] | "Route: \(.name) | Paths: \(.paths | join(", "))"'

# 4. Check all Consumers (Username & ID)
curl -s http://localhost:8001/consumers | jq -r '.data[] | "Consumer: \(.username) (ID: \(.id))"'

# 5. Verify DORS Consumer & Credentials
curl -s http://localhost:8001/consumers/va_dors_consumer/basic-auth | jq .

# 6. Verify Active Plugins on DORS Service
curl -s http://localhost:8001/services/imops-dors-incident-service/plugins | jq -r '.data[] | "Plugin: \(.name) (Enabled: \(.enabled))"'
```

#### Windows (PowerShell):
```powershell
# Check all Routes (Name, Paths & Service ID)
(curl.exe -s http://localhost:8001/routes | ConvertFrom-Json).data | ForEach-Object { "Route: $($_.name) | Paths: $($_.paths -join ', ') | Service ID: $($_.service.id)" }

# Check all Consumers (Username & ID)
(curl.exe -s http://localhost:8001/consumers | ConvertFrom-Json).data | ForEach-Object { "Consumer: $($_.username) (ID: $($_.id))" }
```

### 11.2 Accessing Kong Manager from Remote Workstation (`vg`)

If opening the Kong Manager dashboard from a browser on the `vg` machine at `http://<WEBAPP_IP>:8002`, ensure that `KONG_ADMIN_GUI_API_URL` in `docker-compose.yml` on `webapp` is set to `http://<WEBAPP_IP>:8001` (not `localhost`):

```yaml
KONG_ADMIN_GUI_URL: http://<WEBAPP_IP>:8002
KONG_ADMIN_GUI_API_URL: http://<WEBAPP_IP>:8001
```

This ensures the browser running on `vg` fetches live service and route data from the `webapp` server rather than failing to reach `localhost:8001`.



