# Digital Twin API Provider - Kong Gateway Implementation Guide

This document provides the complete architecture, provisioning instructions, authentication specifications, and step-by-step testing procedures for using **Kong Gateway OSS 3.9** as the secure API Provider and Real-Time Egress Gateway for external **Digital Twins** (e.g., Vizzio, Taylor, Proscalar).

---

## 1. Executive Summary & Architecture

Digital Twin platforms interact with the Common Data Environment (CDE) / iMOPS backend via a **hybrid communication pattern**:

1. **Reconciliation Loop (Periodic REST Polling):**
   * Digital Twins poll spatial hierarchy and incident tallies at regular intervals (e.g., every 5s–30s) to synchronize the 3D scene model.
   * **Kong Gateway Role:** Provides centralized ingress routing (`/api/visualization/*`), enforces perimeter security via **HTTP Basic Authentication** (`hide_credentials: false`) which passes the credentials directly to the upstream backend, applies burst rate limiting (120 req/min), and handles CORS preflights for WebGL/browser runtimes.

2. **Real-Time Reactive Stream (Bi-Directional WebSocket):**
   * Digital Twins establish a persistent channel to receive push notifications for critical events (camera offline, fire alarm, intrusion) immediately.
   * Digital Twin operators can send two-way commands back over the same socket (topic subscription, acknowledge incident, focus 3D camera).
   * **Kong Gateway Role:** Transparently upgrades HTTP requests to RFC 6455 WebSockets (`101 Switching Protocols`), enforces perimeter security, and maintains a 5-minute keepalive timeout (`read_timeout: 300000ms`, `write_timeout: 300000ms`).

```
                    ┌────────────────────────────────────────────────────────┐
                    │          Digital Twin Client (Vizzio / Taylor)         │
                    │          (Browser / WebGL / Three.js Engine)           │
                    └───────────────────┬────────────────┬───────────────────┘
                                        │                │
           1. REST Polling (Reconcil)   │                │ 2. Real-Time Push Stream
              (Basic Auth: user/pass)   │                │    (ws://... /ws?apikey=...)
                                        ▼                ▼
┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│ Kong Gateway OSS 3.9 (Port 8088 / 8443)                                                     │
│  ├── Service: imops-twin-rest-service     (Path: /api/visualization, /api/auth)             │
│  │   ├── Plugin: cors                     (Permissive for 3D/WebGL browser origins)         │
│  │   ├── Plugin: rate-limiting            (120 req/min burst protection)                    │
│  │   └── Route: twin-visualization-route  (Plugin: basic-auth, hide_credentials: false)     │
│  ├── Service: imops-twin-realtime-service (Path: /ws, /socket.io)                           │
│  │   ├── Timeouts: read=300s, write=300s  (Long-lived persistent WebSocket streaming)      │
│  │   └── Plugin: cors                     (Allows WebSocket handshake headers)              │
│  └── Consumer: vizzio-twin-consumer       (Basic Auth: vizzio@imops.local)                  │
└───────────────────────────────────────┬────────────────┬────────────────────────────────────┘
                                        │                │
                                        │ (Basic Auth    │ (RFC 6455 Frames)
                                        │  Pass-Through) │
                                        ▼                ▼
┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│ Target Upstream Backend (host.docker.internal:13000 or custom host)                         │
│  ├── REST Endpoints: /api/visualization/hierarchy, /api/visualization/incidents            │
│  │   └── Directly verifies Authorization: Basic <base64(user:password)>                     │
│  ├── WebSocket Engine: /ws (or /socket.io)                                                  │
│  └── Event Bus / Redis PubSub (Broadcasts incidents live to connected twin clients)        │
└─────────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Authentication Architecture

### 2.1 REST Endpoints (`/api/visualization/*`) — HTTP Basic Auth
The upstream iMOPS backend natively supports **HTTP Basic Authentication**. Rather than requiring clients to manage expiring JWT tokens:
* The client passes `Authorization: Basic <base64(username:password)>`.
* Kong's `basic-auth` plugin authenticates the credentials at the perimeter.
* Because `hide_credentials = false`, Kong **preserves and forwards** the `Authorization: Basic ...` header to the upstream backend.
* Upstream validates the credentials and executes the request.

| Parameter | Value |
| :--- | :--- |
| **Username** | `vizzio@imops.local` |
| **Password** | `xAJHkkm7m3V5MhtF0xGM` |
| **Base64 String** | `dml6emlvQGltb3BzLmxvY2FsOnhBSkhra203bTNWNU1odEYweEdN` |
| **Header** | `Authorization: Basic dml6emlvQGltb3BzLmxvY2FsOnhBSkhra203bTNWNU1odEYweEdN` |

### 2.2 WebSocket Endpoints (`/ws`) — API Key & In-Socket Auth
In browser runtimes (e.g. WebGL / Three.js), the native `new WebSocket(url)` API cannot attach arbitrary HTTP headers during the handshake. Therefore:
* **Perimeter Validation (Kong):** Passed via query parameter: `ws://localhost:8088/ws?apikey=vizzio-digital-twin-key-2026`.
* **In-Socket Authentication:** The client can also send credentials in the first frame after connection:
  ```json
  { "action": "AUTH", "username": "vizzio@imops.local", "password": "xAJHkkm7m3V5MhtF0xGM" }
  ```

---

## 3. Implemented Files & Assets

| File | Type | Description |
| :--- | :--- | :--- |
| [`scripts/setup_twin_provider.ps1`](file:///c:/Projects/cde/apigw/scripts/setup_twin_provider.ps1) | PowerShell Script | Automated provisioning script for Windows. Configures services, routes, CORS, rate limiting, `basic-auth` (with `hide_credentials: false`), and consumer credentials. |
| [`scripts/setup_twin_provider.sh`](file:///c:/Projects/cde/apigw/scripts/setup_twin_provider.sh) | Bash Script | Linux / Docker parity script for CI/CD environments. |
| [`scripts/mock_twin_backend.js`](file:///c:/Projects/cde/apigw/scripts/mock_twin_backend.js) | Node.js Backend | Zero-dependency mock server providing both REST reconciliation endpoints and an RFC 6455 native WebSocket server broadcasting simulated alerts. |
| [`docs/twin_simulator.html`](file:///c:/Projects/cde/apigw/docs/twin_simulator.html) | Web Application | High-fidelity, dark-mode Digital Twin operations simulator demonstrating live REST polling with Basic Auth, WebSocket streaming, and 2-way commands. |

---

## 4. Provisioning Instructions

### Prerequisites
* Docker running with Kong Gateway container (`docker compose up -d`).
* Kong Admin API accessible on `http://localhost:8001`.
* Public Proxy port `8088` exposed.

### Option A: Windows PowerShell
```powershell
# 1. Default (Upstream defaults to localhost:13000):
powershell.exe -ExecutionPolicy Bypass -File .\scripts\setup_twin_provider.ps1

# 2. Deploy against a specific IP:
powershell.exe -ExecutionPolicy Bypass -File .\scripts\setup_twin_provider.ps1 "10.65.51.252"

# 3. Test with the local Mock Backend (Port 3001):
powershell.exe -ExecutionPolicy Bypass -File .\scripts\setup_twin_provider.ps1 "localhost:3001"
```

### Option B: Linux / macOS Bash
```bash
chmod +x ./scripts/setup_twin_provider.sh
./scripts/setup_twin_provider.sh "localhost:13000"
```

---

## 5. Step-by-Step Testing & Verification Guide

Follow these sequential steps to verify all endpoints and security behaviors.

---

### Step 1: Verify Kong Gateway Health
Ensure Kong Gateway is running and healthy:

**Windows `curl.exe` (CMD & PowerShell):**
```cmd
curl.exe -i http://localhost:8001/status
```

**PowerShell (`Invoke-RestMethod`):**
```powershell
Invoke-RestMethod -Uri "http://localhost:8001/status" | ConvertTo-Json
```

**Expected Output:** Status report showing active database connection (`database: { reachable: true }`) and server operational status.

---

### Step 2: Test REST Reconciliation with HTTP Basic Auth

#### 2A. Query Site Hierarchy Tree (SOV @ 38ALT)
Query the full building, floor, and zone hierarchy for the site:

**Windows `curl.exe` (CMD & PowerShell):**
```cmd
curl.exe -i -u "vizzio@imops.local:xAJHkkm7m3V5MhtF0xGM" "http://localhost:8088/api/visualization/hierarchy?siteName=SOV%20%40%2038ALT&tree=true"
```

**PowerShell (`Invoke-RestMethod`):**
```powershell
$base64Auth = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("vizzio@imops.local:xAJHkkm7m3V5MhtF0xGM"))
$headers = @{ "Authorization" = "Basic $base64Auth" }

$resp = Invoke-RestMethod `
  -Uri "http://localhost:8088/api/visualization/hierarchy?siteName=SOV%20%40%2038ALT&tree=true" `
  -Headers $headers

$resp | ConvertTo-Json -Depth 3
```

**Linux / macOS `curl`:**
```bash
curl -i "http://localhost:8088/api/visualization/hierarchy?siteName=SOV%20%40%2038ALT&tree=true" \
  -u "vizzio@imops.local:xAJHkkm7m3V5MhtF0xGM"
```

**Expected Result:**
* `HTTP/1.1 200 OK`
* Header `Server: kong/3.9.3`
* Header `X-Kong-Upstream-Latency: <N> ms`
* Header `RateLimit-Limit: 120` & `RateLimit-Remaining: 119`
* Response body contains `SOV @ 38ALT` hierarchy tree with floors, devices, and zones.

---

#### 2B. Query Incident Summary & Tally
Query active and historical incidents for synchronization:

**Windows `curl.exe` (CMD & PowerShell):**
```cmd
curl.exe -i -u "vizzio@imops.local:xAJHkkm7m3V5MhtF0xGM" "http://localhost:8088/api/visualization/incidents?siteName=SOV%20%40%2038ALT&daysBack=365&page=1&limit=5"
```

**PowerShell (`Invoke-RestMethod`):**
```powershell
$base64Auth = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("vizzio@imops.local:xAJHkkm7m3V5MhtF0xGM"))
$headers = @{ "Authorization" = "Basic $base64Auth" }

$resp = Invoke-RestMethod `
  -Uri "http://localhost:8088/api/visualization/incidents?siteName=SOV%20%40%2038ALT&daysBack=365&page=1&limit=5" `
  -Headers $headers

$resp.data.summary | ConvertTo-Json
$resp.data.typeSummary | ConvertTo-Json
```

**Expected Result:** Returns active incident counts (`attend_now`, `active`, `pending`) and breakdown by incident type (`Loitering`, `Intrusion`, `Fire`).

---

### Step 3: Security & Negative Testing

#### 3A. Request Without Authentication (Should Fail)

**Windows `curl.exe` (CMD & PowerShell):**
```cmd
curl.exe -i "http://localhost:8088/api/visualization/hierarchy?siteName=SOV%20%40%2038ALT&tree=true"
```

**PowerShell (`Invoke-RestMethod`):**
```powershell
try {
    Invoke-RestMethod -Uri "http://localhost:8088/api/visualization/hierarchy?siteName=SOV%20%40%2038ALT&tree=true"
    Write-Host "FAILED: Endpoint allowed unauthenticated request!" -ForegroundColor Red
} catch {
    Write-Host "PASSED: Blocked with $($_.Exception.Message)" -ForegroundColor Green
}
```

**Expected Result:**
* `HTTP/1.1 401 Unauthorized`
* Header `WWW-Authenticate: Basic realm="service"`
* Body: `{"message":"Unauthorized"}`

#### 3B. Request with Invalid Password (Should Fail)

**Windows `curl.exe` (CMD & PowerShell):**
```cmd
curl.exe -i -u "vizzio@imops.local:wrong_password" "http://localhost:8088/api/visualization/hierarchy?siteName=SOV%20%40%2038ALT&tree=true"
```

**PowerShell (`Invoke-RestMethod`):**
```powershell
$badAuth = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("vizzio@imops.local:wrong_password"))
try {
    Invoke-RestMethod `
      -Uri "http://localhost:8088/api/visualization/hierarchy?siteName=SOV%20%40%2038ALT&tree=true" `
      -Headers @{ Authorization = "Basic $badAuth" }
    Write-Host "FAILED: Allowed invalid password!" -ForegroundColor Red
} catch {
    Write-Host "PASSED: Blocked with $($_.Exception.Message)" -ForegroundColor Green
}
```

**Expected Result:**
* `HTTP/1.1 401 Unauthorized` directly rejected at the Kong perimeter.

---

### Step 4: Real-Time WebSocket Handshake & Stream Test

The live iMOPS upstream backend uses **Socket.IO (Engine.IO v4)** on `/socket.io/` for bi-directional streaming.

> [!NOTE]
> If calling `/ws` directly against the production backend, the upstream SPA web server returns `200 OK (text/html)` instead of upgrading the protocol, which causes Kong to return `502 Bad Gateway: An invalid response was received from the upstream server`.
> For the live backend, connect to the Socket.IO route `/socket.io/`. (If testing with `mock_twin_backend.js`, `/ws` is supported).

#### Option 4A: Windows `curl.exe` (Socket.IO WebSocket Upgrade Handshake)
Inspect the `101 Switching Protocols` handshake through Kong Gateway (:8088):
```cmd
curl.exe -i --max-time 3 -N -H "Connection: Upgrade" -H "Upgrade: websocket" -H "Sec-WebSocket-Version: 13" -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" "http://localhost:8088/socket.io/?EIO=4&transport=websocket"
```

**Expected Result:**
```http
HTTP/1.1 101 Switching Protocols
Connection: upgrade
Upgrade: websocket
Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=
Server: kong/3.9.3
X-Kong-Upstream-Latency: 5
X-Kong-Proxy-Latency: 1
Via: 1.1 kong/3.9.3

0{"sid":"...","upgrades":[],"pingInterval":25000,"pingTimeout":20000,"maxPayload":1000000}
```

#### Option 4B: Windows `curl.exe` (Socket.IO Initial Polling Handshake)
Test the HTTP polling handshake that Socket.IO clients use to negotiate connection:
```cmd
curl.exe -i "http://localhost:8088/socket.io/?EIO=4&transport=polling"
```

**Expected Result:**
```http
HTTP/1.1 200 OK
Content-Type: text/plain; charset=UTF-8
Server: kong/3.9.3
X-Kong-Upstream-Latency: 5

0{"sid":"...","upgrades":["websocket"],"pingInterval":25000,"pingTimeout":20000,"maxPayload":1000000}
```

#### Option 4C: Node.js CLI Script (Stream Frame Receiver)
```bash
node -e "
const http = require('http');
const crypto = require('crypto');
const req = http.request({
  host: 'localhost',
  port: 8088,
  path: '/ws?apikey=vizzio-digital-twin-key-2026',
  headers: {
    'Connection': 'Upgrade',
    'Upgrade': 'websocket',
    'Sec-WebSocket-Key': crypto.randomBytes(16).toString('base64'),
    'Sec-WebSocket-Version': '13'
  }
});
req.on('upgrade', (res, socket) => {
  console.log('✅ Connected via Kong Gateway! Status Code:', res.statusCode);
  console.log('✅ Server Header:', res.headers.server);
  socket.on('data', buf => {
    console.log('📥 Stream Frame Received:', buf.toString('utf8'));
    socket.destroy();
    process.exit(0);
  });
});
req.on('error', err => console.error('Connection error:', err.message));
req.end();
"
```

**Expected Result:**
```text
✅ Connected via Kong Gateway! Status Code: 101
✅ Server Header: kong/3.9.3
📥 Stream Frame Received: {"type":"INCIDENT_ALERT", ...}
```

---

### Step 5: Interactive Visual Verification (`twin_simulator.html`)

A full browser-based Digital Twin simulator is provided in [`docs/twin_simulator.html`](file:///c:/Projects/cde/apigw/docs/twin_simulator.html).

1. **Open the Simulator:**
   Double-click or open `twin_simulator.html` in Chrome, Edge, or Firefox.

2. **Check Configuration in Top Bar:**
   * **Kong Proxy:** `http://localhost:8088`
   * **Username:** `vizzio@imops.local`
   * **Password:** `xAJHkkm7m3V5MhtF0xGM`
   * **WS API Key:** `vizzio-digital-twin-key-2026`

3. **Verify Reconciliation Poller (Left Panel):**
   * The simulator polls `http://localhost:8088/api/visualization/hierarchy` every 5 seconds using Basic Auth.
   * Real-time metrics show Kong proxy latency (sub-10ms), total floors (6), and total zones (13).
   * Spatial floor breakdown automatically renders (Level 1 Lift Lobby up to Level 6 Rooftop).

4. **Verify WebSocket Push Stream (Right Panel):**
   * Click **Connect Stream** in the top bar.
   * The status badge turns green (`Connected (Kong :8088)`).
   * As incidents occur or are simulated, alert cards automatically appear on screen in real time.

5. **Test Two-Way Commands:**
   * Click **Acknowledge** on any incident card to send an update back over the open WebSocket.
   * Click **Trigger Sim Alarm** or **Focus Level 4 War Room** to test bi-directional socket telemetry.

---

### Step 6: Postman Integration

To use the Postman Collection ([`docs/iMops-List (Vizzio).postman_collection.json`](file:///c:/Projects/cde/apigw/docs/iMops-List%20%28Vizzio%29.postman_collection.json)) through Kong:

1. Open Environment ([`docs/iMops-Lite (Taylor).postman_environment.json`](file:///c:/Projects/cde/apigw/docs/iMops-Lite%20%28Taylor%29.postman_environment.json)).
2. Set `BACKEND_API` to `http://localhost:8088`.
3. Set the authorization on the requests to **Basic Auth** with:
   * **Username:** `{{VIZZIO_USER}}` (`vizzio@imops.local`)
   * **Password:** `{{VIZZIO_PASS}}` (`xAJHkkm7m3V5MhtF0xGM`)
4. Run `Get Site Tree (HQ)`:
   `GET {{BACKEND_API}}/api/visualization/hierarchy?siteName=SOV%20%40%2038ALT&tree=true`
   Requests are authenticated and proxied with zero code changes required on the backend.

---

## 6. Multi-Site Topic Partitioning & Backend Engineering Handover

In multi-site deployments, a Digital Twin viewing **SOV @ 38ALT** must only receive events for SOV @ 38ALT, while a twin viewing **DORS** only receives DORS events.

### How it Works:
* **Digital Twin connects** via Kong Gateway on `/socket.io/`.
* **Digital Twin declares its site** by emitting:
  ```json
  socket.emit("subscribe", { "siteName": "SOV @ 38ALT" });
  ```
* **Upstream assigns socket to room:** `socket.join("site:SOV @ 38ALT")`.
* **When incidents occur:** The backend emits alerts only to the target room:
  ```javascript
  io.to(`site:${incident.site}`).emit("incident:new", incident);
  ```

> [!TIP]
> **Upstream Engineering Handover Guide:**  
> A dedicated, developer-ready specification document has been created for the backend team:  
> 👉 [**Upstream WebSocket & Topic Specification**](file:///c:/Projects/cde/apigw/docs/upstream_websocket_specification.md)  
> *Includes payload schemas, connection events, and drop-in Node.js / Socket.IO code snippets to provide directly to the upstream engineering team.*

