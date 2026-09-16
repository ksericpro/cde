# Digital Twin API Provider - Kong Gateway Implementation Guide

This document summarizes the architecture, implementation, provisioning instructions, and end-to-end testing procedures for using **Kong Gateway OSS 3.9** as the secure API Provider and Real-Time Egress Gateway for external **Digital Twins** (e.g., Vizzio, Taylor, Proscalar).

---

## 1. Executive Summary & Architecture

Digital Twin platforms interact with the Common Data Environment (CDE) / iMOPS backend via a **hybrid communication pattern**:

1. **Reconciliation Loop (Periodic REST Polling):**
   * Digital Twins poll spatial hierarchy and incident tallies at regular intervals (e.g., every 5s–30s) to synchronize the 3D scene model.
   * **Kong Gateway Role:** Provides centralized ingress routing (`/api/visualization/*`), CORS preflight handling for WebGL/browser runtimes, burst rate limiting (120 req/min), and optional caching to protect backend databases.
2. **Real-Time Reactive Stream (Bi-Directional WebSocket):**
   * Digital Twins establish a persistent channel to receive push notifications for critical events (camera offline, fire alarm, intrusion) immediately.
   * Digital Twin operators can send two-way commands back over the same socket (topic subscription, acknowledge incident, focus 3D camera).
   * **Kong Gateway Role:** Transparently upgrades HTTP requests to RFC 6455 WebSockets (`101 Switching Protocols`), enforces perimeter security via API keys, and maintains a 5-minute keepalive timeout (`read_timeout: 300000ms`).

```
                    ┌────────────────────────────────────────────────────────┐
                    │          Digital Twin Client (Vizzio / Taylor)         │
                    │          (Browser / WebGL / Three.js Engine)           │
                    └───────────────────┬────────────────┬───────────────────┘
                                        │                │
           1. REST Polling (Reconcil)   │                │ 2. Real-Time Push Stream
              (GET Hierarchy, Incidents)│                │    (ws://... /ws)
                                        ▼                ▼
┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│ Kong Gateway OSS 3.9 (Port 8088 / 8443)                                                     │
│  ├── Service: imops-twin-rest-service     (Path: /api/visualization, /api/auth)             │
│  │   ├── Plugin: cors                     (Permissive for 3D/WebGL browser origins)         │
│  │   ├── Plugin: rate-limiting            (120 req/min burst protection)                    │
│  │   └── Plugin: request-transformer      (Option 2: Auto-injects backend Bearer token)     │
│  ├── Service: imops-twin-realtime-service (Path: /ws, /socket.io)                           │
│  │   ├── Timeouts: read=300s, write=300s  (Long-lived persistent WebSocket streaming)      │
│  │   └── Plugin: cors                     (Allows WebSocket handshake headers)              │
│  └── Consumer: vizzio-twin-consumer       (API Key: vizzio-digital-twin-key-2026)           │
└───────────────────────────────────────┬────────────────┬────────────────────────────────────┘
                                        │                │
                                        ▼                ▼
┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│ Target Upstream Backend (host.docker.internal:13000 or custom host)                         │
│  ├── REST Endpoints: /api/visualization/hierarchy, /api/visualization/incidents            │
│  └── WebSocket Engine: /ws (or /socket.io)                                                  │
└─────────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. What Was Implemented

| File | Type | Description |
| :--- | :--- | :--- |
| [`scripts/setup_twin_provider.ps1`](file:///c:/Projects/cde/apigw/scripts/setup_twin_provider.ps1) | PowerShell Script | Automated provisioning script for Windows environments. Dynamically configures Kong services, routes, CORS, rate limiting, and consumers. Supports dynamic upstream host resolution. |
| [`scripts/setup_twin_provider.sh`](file:///c:/Projects/cde/apigw/scripts/setup_twin_provider.sh) | Bash Script | Linux / Docker parity script for CI/CD and containerized deployment. |
| [`scripts/mock_twin_backend.js`](file:///c:/Projects/cde/apigw/scripts/mock_twin_backend.js) | Node.js Backend | Zero-dependency mock server providing both REST reconciliation endpoints and an RFC 6455 native WebSocket server broadcasting simulated alerts and processing 2-way commands. |
| [`docs/twin_simulator.html`](file:///c:/Projects/cde/apigw/docs/twin_simulator.html) | Web Application | High-fidelity, dark-mode Digital Twin operations simulator demonstrating live REST polling, WebSocket streaming, 2-way commands, and Kong telemetry. |

---

## 3. Provisioning Steps (How to Run the Setup Scripts)

The setup script provisions all necessary Kong Services, Routes, Plugins, and Consumers in under 3 seconds. It features **dynamic host resolution**, making it adaptable to any environment without hardcoding.

### Prerequisites
* Kong Gateway container running with Admin API accessible on `http://localhost:8001` (or your remote admin URL).
* Port `8088` (Public Proxy HTTP) exposed.

### Option A: Windows PowerShell

Run `setup_twin_provider.ps1` from the repository root or `scripts/` directory:

```powershell
# 1. Default (Upstream defaults to localhost:13000):
powershell.exe -ExecutionPolicy Bypass -File .\scripts\setup_twin_provider.ps1

# 2. Deploying against a specific IP (automatically defaults to port 13000):
powershell.exe -ExecutionPolicy Bypass -File .\scripts\setup_twin_provider.ps1 "10.65.51.252"

# 3. Deploying against a specific Host and Port:
powershell.exe -ExecutionPolicy Bypass -File .\scripts\setup_twin_provider.ps1 "10.65.51.252:13000"

# 4. Deploying against a full URL:
powershell.exe -ExecutionPolicy Bypass -File .\scripts\setup_twin_provider.ps1 "http://prod-imops.internal:13000"

# 5. Testing with the local Mock Backend (Port 3001):
powershell.exe -ExecutionPolicy Bypass -File .\scripts\setup_twin_provider.ps1 "localhost:3001"
```

#### Script Parameters:
* `-UpstreamHost` (Position 0, default: `"localhost:13000"`): Target backend IP, host, or URL. Automatically maps `localhost` / `127.0.0.1` to `host.docker.internal` so Kong inside Docker can reach the host machine.
* `-AdminUrl` (Position 1, default: `"http://localhost:8001"`): Kong Admin API URL.
* `-ApiKey` (Position 2, default: `"vizzio-digital-twin-key-2026"`): Consumer API key for Digital Twin authentication.

---

### Option B: Linux / macOS Bash

```bash
# Make script executable
chmod +x ./scripts/setup_twin_provider.sh

# 1. Default (localhost:13000):
./scripts/setup_twin_provider.sh

# 2. Custom Production IP:
./scripts/setup_twin_provider.sh "10.65.51.252"

# 3. Custom Host & Port with Custom API Key:
./scripts/setup_twin_provider.sh "10.65.51.252:13000" "http://localhost:8001" "my-production-key"
```

---

## 4. How to Test & Verify

### Test 1: REST Reconciliation via Kong Proxy (Port 8088)

Verify that spatial hierarchy and incident endpoints are proxied through Kong with rate limiting and CORS headers:

#### Using cURL:
```bash
# Query Site Hierarchy (SOV @ 38ALT)
curl -i "http://localhost:8088/api/visualization/hierarchy?siteName=SOV%20%40%2038ALT&tree=true" \
  -H "apikey: vizzio-digital-twin-key-2026"
```

#### Using PowerShell:
```powershell
$headers = @{ "apikey" = "vizzio-digital-twin-key-2026" }
Invoke-RestMethod -Uri "http://localhost:8088/api/visualization/hierarchy?siteName=SOV%20%40%2038ALT&tree=true" -Headers $headers | ConvertTo-Json -Depth 3
```

#### Expected Verification Output:
* `HTTP/1.1 200 OK`
* Header `Server: kong/3.9.3`
* Header `X-Kong-Upstream-Latency: <N> ms`
* Header `X-Kong-Proxy-Latency: <N> ms`
* Header `RateLimit-Limit: 120` & `RateLimit-Remaining: 119`
* Response body contains `SOV @ 38ALT` hierarchy tree with floors, devices, and zones.

---

### Test 2: Real-Time WebSocket Handshake & Stream via Kong Proxy

Test that Kong Gateway properly negotiates `HTTP 101 Switching Protocols` and passes real-time frames over `ws://localhost:8088/ws`.

#### Quick Node.js Test One-Liner:
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
  console.log('✅ Connected via Kong Gateway! Status:', res.statusCode);
  console.log('Server Header:', res.headers.server);
  socket.on('data', buf => {
    console.log('📥 Received Stream Frame:', buf.toString('utf8'));
    socket.destroy();
    process.exit(0);
  });
});
req.end();
"
```

#### Expected Output:
```text
✅ Connected via Kong Gateway! Status: 101
Server Header: kong/3.9.3
📥 Received Stream Frame: {"type":"INCIDENT_ALERT","incident":{"id":"INC-101",...}}
```

---

### Test 3: Interactive Visual Verification using `twin_simulator.html`

We have provided a browser-based simulator in [`docs/twin_simulator.html`](file:///c:/Projects/cde/apigw/docs/twin_simulator.html).

#### Step-by-Step Instructions:
1. **Start the Mock Backend** (if testing in offline or staging mode):
   ```powershell
   node .\scripts\mock_twin_backend.js
   ```
2. **Point Kong to the Mock Backend:**
   ```powershell
   .\scripts\setup_twin_provider.ps1 "host.docker.internal:3001"
   ```
3. **Open the Simulator:**
   * Open [`twin_simulator.html`](file:///c:/Projects/cde/apigw/docs/twin_simulator.html) directly in Chrome, Edge, or Firefox.
4. **Verify the Features:**
   * **Reconciliation Loop (Left Panel):** Notice the live countdown timer polling `http://localhost:8088/api/visualization/hierarchy` every 5 seconds. Kong latency and synchronized floors (L1 to L6) update in real time.
   * **Real-Time WebSocket Stream (Right Panel):** Click **Connect Stream** in the top bar. The status badge turns emerald (`Connected (Kong :8088)`), and live incident cards automatically appear as they are pushed.
   * **Two-Way Commands:** Click **Acknowledge** on an active alert card, or click **Trigger Sim Alarm** / **Focus Level 4 War Room**. Notice the instant state reflection over the open WebSocket without refreshing the page.
   * **Audit Log (Bottom Console):** Inspect each request and frame showing exact timestamps, latency, and Kong proxy headers.

---

## 5. Postman Collection Integration

To use the provided Postman collection ([`docs/iMops-List (Vizzio).postman_collection.json`](file:///c:/Projects/cde/apigw/docs/iMops-List%20%28Vizzio%29.postman_collection.json)) through Kong Gateway:

1. Open your Postman Environment ([`docs/iMops-Lite (Taylor).postman_environment.json`](file:///c:/Projects/cde/apigw/docs/iMops-Lite%20%28Taylor%29.postman_environment.json)).
2. Update the `BACKEND_API` variable:
   * **Old Value:** `http://localhost:3000`
   * **New Kong Value:** `http://localhost:8088`
3. Add a new environment variable:
   * `API_KEY`: `vizzio-digital-twin-key-2026`
4. Run the requests in order:
   * `POST {{BACKEND_API}}/api/auth/login` $\rightarrow$ Obtains JWT token.
   * `GET {{BACKEND_API}}/api/visualization/hierarchy?siteName=SOV%20%40%2038ALT&tree=true` $\rightarrow$ Routes through Kong Gateway with sub-10ms proxy latency.
