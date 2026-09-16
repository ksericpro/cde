# AI Prompt: Implementing Real-Time Multi-Site WebSocket Streaming in iMOPS (Backend & Frontend)

> **Instructions for User:** Copy and paste the prompt below directly into your iMOPS AI coding assistant or ticket system. It contains full requirements, architectural specifications, and reference code for both the **Backend** and **Frontend**.

---

```markdown
# Role & Objective
You are a senior full-stack engineer working on the iMOPS / Common Data Environment (CDE) platform.

We need to implement **real-time, multi-site incident streaming** using **Socket.IO (Engine.IO v4)** across both the **iMOPS Backend** and **iMOPS Frontend / Digital Twin Viewers**. 

Currently, clients poll REST endpoints (`/api/visualization/incidents` and `/api/visualization/hierarchy`). We need live incident triggers (from Video Analytics cameras, IoT sensors, and operators) to be pushed instantly to connected users, **partitioned strictly by site** (e.g. `SOV @ 38ALT`, `DORS`, `SICC`).

---

## Architecture Overview

1. **Proxy Layer:** Traffic is routed through Kong Gateway (`:8088`), which forwards `/socket.io/*` and `/api/*` directly to our upstream iMOPS backend (`:13000`).
2. **Room / Topic Segregation:** Digital Twin clients only monitor one physical site at a time. The backend must use Socket.IO rooms (`site:<siteName>`) so that incidents occurring at `SOV @ 38ALT` are ONLY pushed to clients currently viewing `SOV @ 38ALT`.

```
[ Camera / Sensor Alert ] 
       │
       ▼
POST /api/incidents/monitor
       │
       ├── 1. Persist to Database (MongoDB)
       └── 2. io.to("site:" + incident.site).emit("incident:new", incident)
                    │
                    ▼ (Tunneled via Kong Gateway :8088/socket.io)
       ┌────────────┴────────────┐
       ▼                         ▼
 [ Frontend: SOV @ 38ALT ]  [ Frontend: DORS ]
 (Receives alert instantly)  (No cross-talk)
```

---

## Part 1: Backend Implementation Requirements

### 1. Attach Socket.IO to HTTP Server
* Mount Socket.IO to the existing HTTP/Express server instance listening on port `13000`.
* Path must be `/socket.io`.
* Configure CORS to allow incoming connections (`origins: "*"`).
* Enable transports: `["websocket", "polling"]`.

### 2. Topic / Room Subscription Handlers
When a client connects:
* Listen for `subscribe`:
  ```json
  { "siteName": "SOV @ 38ALT", "siteCode": "SOV_38ALT" }
  ```
  * Join the client to room: `socket.join(`site:${data.siteName}`)`.
  * Emit back acknowledgment: `socket.emit("subscribed", { topic: `site:${data.siteName}`, status: "OK" })`.
* Listen for `unsubscribe`:
  ```json
  { "siteName": "SOV @ 38ALT" }
  ```
  * Leave room: `socket.leave(`site:${data.siteName}`)`.
* Listen for `acknowledge_incident`:
  ```json
  { "incidentId": "INC-001", "siteName": "SOV @ 38ALT", "user": "operator@imops.local" }
  ```
  * Update incident status in database to `acknowledged`.
  * Broadcast to room: `io.to(`site:${data.siteName}`).emit("incident:updated", { ... })`.

### 3. Hook into Incident Creation (`POST /api/incidents/monitor`)
In your incident controller/service (where incoming camera triggers and manual incidents are saved):
* Immediately after saving the incident to MongoDB/PostgreSQL:
  ```javascript
  const room = `site:${savedIncident.site}`;
  io.to(room).emit("incident:new", {
    eventId: savedIncident._id,
    incidentNumber: savedIncident.incidentNumber,
    site: savedIncident.site,
    building: savedIncident.building || "HQ Building",
    floor: savedIncident.floor || "Floor 1",
    zone: savedIncident.zone || "Zone 1",
    incidentType: savedIncident.incidenttype || savedIncident.incidentType,
    eventName: savedIncident.eventName,
    severity: savedIncident.priority || "critical",
    status: savedIncident.status || "active",
    timestamp: Math.floor(Date.now() / 1000),
    detectedAt: savedIncident.detectedAt || new Date().toISOString(),
    metadata: savedIncident.metadata || {}
  });
  ```

---

## Part 2: Frontend Implementation Requirements

### 1. Socket.IO Client Setup
* Create a dedicated real-time service / hook (e.g. `useRealtimeIncidents(siteName)`).
* Connect using `socket.io-client` pointing to the gateway URL:
  ```javascript
  const socket = io(GATEWAY_URL, {
    path: "/socket.io",
    transports: ["websocket", "polling"],
    reconnectionAttempts: 10,
    reconnectionDelay: 2000
  });
  ```

### 2. Auto-Subscribe on Site Change
* Whenever the active site changes (e.g. user selects `SOV @ 38ALT`):
  * Emit `subscribe`:
    ```javascript
    socket.emit("subscribe", { siteName: currentSiteName });
    ```
* If switching away or unmounting:
  * Emit `unsubscribe` and clean up listeners.

### 3. Real-Time UI Reactive Updates
* Listen for `incident:new`:
  * Prepend the new incident to the live incident state list (`setIncidents(prev => [newIncident, ...prev])`).
  * Increment the active incidents counter badge.
  * Trigger a sound effect / toast alert ("Critical Incident: Intrusion at Main Gate").
  * Flash the affected floor/zone in the 3D Digital Twin model.
* Listen for `incident:updated`:
  * Update the existing incident card status in state (e.g., badge changes from `Attend Now` to `Acknowledged`).

---

## Part 3: Verification & Acceptance Criteria

1. **Local Socket Handshake Test:**
   ```cmd
   curl.exe -i --max-time 3 -N -H "Connection: Upgrade" -H "Upgrade: websocket" -H "Sec-WebSocket-Version: 13" -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" "http://localhost:8088/socket.io/?EIO=4&transport=websocket"
   ```
   *Must return `HTTP/1.1 101 Switching Protocols` with `Server: kong/3.9.3`.*

2. **Multi-Site Isolation Test:**
   * Open Client A subscribed to `SOV @ 38ALT`.
   * Open Client B subscribed to `DORS`.
   * Trigger an incident via `POST /api/incidents/monitor` for `SOV @ 38ALT`.
   * **Result:** Client A displays the alert instantly (<100ms). Client B receives zero messages.
```
