# Upstream Backend Engineering Specification: Real-Time WebSocket & Topic Subscription for Digital Twins

**Target Audience:** Upstream Backend Engineering Team (iMOPS / CDE Backend Developers)  
**Gateway Entrypoint:** Kong Gateway OSS 3.9 (Port 8088) $\rightarrow$ Upstream Ingress (Port 13000)  
**Protocols:** Socket.IO (Engine.IO v4) / RFC 6455 WebSocket  

---

## 1. Executive Summary & Objective

External Digital Twins (e.g., Vizzio, Taylor, Proscalar) render live 3D models of specific physical sites (e.g., `SOV @ 38ALT`, `DORS`, `SICC`). 

Currently:
1. **REST APIs:** Kong Gateway proxies `/api/visualization/*` to the upstream backend with HTTP Basic Auth (`vizzio@imops.local`). This is fully operational.
2. **Real-Time Stream:** Kong Gateway proxies `/socket.io/*` and `/ws` to upstream port `13000`.

### The Goal for the Upstream Team:
The upstream backend must publish live incident events to connected Digital Twins **segregated by site topic**, so a twin rendering `SOV @ 38ALT` only receives alerts for `SOV @ 38ALT`, while avoiding alerts from other sites.

```
                          ┌──────────────────────────────────────────────┐
                          │   Upstream iMOPS Backend Server (Port 13000) │
                          │   ├── Incident Monitor API                   │
                          │   └── Socket.IO Real-Time Engine             │
                          └──────────────────────┬───────────────────────┘
                                                 │
                  ┌──────────────────────────────┴──────────────────────────────┐
                  ▼                                                             ▼
     [ Room: "site:SOV @ 38ALT" ]                                      [ Room: "site:DORS" ]
                  │                                                             │
                  │ (Tunneled via Kong :8088/socket.io)                         │ (Tunneled via Kong :8088/socket.io)
                  ▼                                                             ▼
    ┌───────────────────────────┐                                 ┌───────────────────────────┐
    │ Digital Twin: SOV @ 38ALT │                                 │    Digital Twin: DORS     │
    │ (Receives ONLY SOV events)│                                 │(Receives ONLY DORS events)│
    └───────────────────────────┘                                 └───────────────────────────┘
```

---

## 2. Technical Requirements

### 2.1 Mount Path & Protocol
* Mount the real-time server on path: `/socket.io` (or provide raw RFC 6455 on `/ws`).
* Bind to the existing HTTP server instance listening on port `13000` (container internal `3000`).

### 2.2 Connection Handshake & Authentication
Digital Twins connect via Kong Gateway (`http://<KONG_HOST>:8088/socket.io/`).

During the connection handshake, accept authentication via:
1. **HTTP Basic Auth Header:** `Authorization: Basic <base64>`
2. **Query Parameter Token:** `http://.../socket.io/?apikey=<API_KEY>&EIO=4&transport=websocket`

Validate credentials against your existing user store (`vizzio@imops.local` or API key).

---

## 3. Topic & Room Naming Specification

To ensure cross-platform compatibility across all Digital Twins, use the following standardized room/topic format:

| Topic Pattern | Example Topic | Description |
| :--- | :--- | :--- |
| `site:<siteName>` | `site:SOV @ 38ALT` | Primary topic matching `siteName` from `/api/visualization/hierarchy?siteName=...` |
| `site_id:<siteId>` | `site_id:6a8289d3e9b4269e23c744d2` | (Optional) Topic matching site MongoDB `_id` |

---

## 4. Client-to-Server Events (Inbound from Digital Twin)

The upstream Socket.IO server must handle the following inbound events from connected clients:

### 4.1 Event: `subscribe` (Join Site Room)
Sent by the Digital Twin immediately after connecting to declare which site it wants to monitor.

**Client Payload:**
```json
{
  "siteName": "SOV @ 38ALT",
  "siteCode": "SOV_38ALT"
}
```

**Backend Action:**
```javascript
socket.on("subscribe", (data) => {
  const room = `site:${data.siteName}`;
  socket.join(room);
  
  // Acknowledge subscription
  socket.emit("subscribed", {
    status: "ACTIVE",
    topic: room,
    timestamp: new Date().toISOString()
  });
});
```

---

### 4.2 Event: `subscribe_sites` (Batch Multi-Site Subscription)
Sent by multi-site dashboards or portfolio twins to subscribe to all assigned sites retrieved from `GET /api/visualization/hierarchy`.

**Client Payload:**
```json
{
  "sites": [
    "AGUSAN DEL NORTE- BUTUAN CITY- BAAN",
    "AGUSAN DEL NORTE-BUENAVISTA",
    "SOV @ 38ALT"
  ]
}
```

**Backend Action:**
```javascript
socket.on("subscribe_sites", (data) => {
  if (!data || !Array.isArray(data.sites)) return;
  
  data.sites.forEach(siteName => {
    socket.join(`site:${siteName}`);
  });

  socket.emit("subscribed_sites", {
    status: "ACTIVE",
    count: data.sites.length,
    timestamp: new Date().toISOString()
  });
});
```

---

### 4.3 Event: `unsubscribe` (Leave Single Site Room)
Sent when the operator switches sites in the 3D viewer.

**Client Payload:**
```json
{
  "siteName": "SOV @ 38ALT"
}
```

**Backend Action:**
```javascript
socket.on("unsubscribe", (data) => {
  const room = `site:${data.siteName}`;
  socket.leave(room);
  socket.emit("unsubscribed", { topic: room });
});
```

---

### 4.4 Event: `unsubscribe_all` (Leave All Site Rooms)
Sent when an operator mutes or pauses all live incoming telemetry.

**Backend Action:**
```javascript
socket.on("unsubscribe_all", () => {
  // Leave all rooms except private socket id room
  for (const room of socket.rooms) {
    if (room !== socket.id) {
      socket.leave(room);
    }
  }
  socket.emit("unsubscribed_all", { status: "PAUSED", timestamp: new Date().toISOString() });
});
```

---

### 4.5 Event: `acknowledge_incident` (Operator 2-Way Command)
Sent when an operator clicks "Acknowledge" inside the 3D twin scene.

**Client Payload:**
```json
{
  "incidentId": "INC-2609-00071",
  "siteName": "SOV @ 38ALT",
  "operator": "vizzio_operator"
}
```

**Backend Action:**
* Update incident status in the database to `attend_now` or `acknowledged`.
* Broadcast `incident:updated` to the room so all viewers update their UI.

---

## 5. Server-to-Client Events (Outbound Broadcast to Twins)

Whenever a new incident is ingested (e.g. from `/api/incidents/monitor`), the backend must broadcast to the site's room:

### 5.1 Event: `incident:new`
Broadcast to room: `io.to("site:SOV @ 38ALT").emit("incident:new", payload)`

**Payload Schema:**
```json
{
  "eventId": "evt-2026-9011",
  "incidentNumber": "INC-2609-00071",
  "site": "SOV @ 38ALT",
  "building": "HQ Building",
  "floor": "Floor 1",
  "zone": "Zone 1",
  "incidentType": "INTRUSION",
  "eventName": "Intrusion: SOV 38ALT Main Gate Perimeter",
  "severity": "CRITICAL",
  "status": "active",
  "timestamp": 1789539200,
  "detectedAt": "2026-09-11T16:16:00.351Z",
  "metadata": {
    "source": "vizzio_va",
    "associatedCamera": "SOV 38ALT Main Gate"
  }
}
```

---

### 5.2 Event: `incident:updated`
Broadcast when incident status changes (acknowledged, escalated, resolved):

```json
{
  "incidentNumber": "INC-2609-00071",
  "site": "SOV @ 38ALT",
  "status": "resolved",
  "resolvedBy": "operator@imops.local",
  "updatedAt": "2026-09-16T08:45:00Z"
}
```

---

## 6. Reference Implementation (Drop-In Node.js Code)

Here is a clean implementation example using `socket.io` that integrates with your existing Express/HTTP server:

```javascript
const { Server } = require("socket.io");

function initDigitalTwinSocket(httpServer) {
  const io = new Server(httpServer, {
    path: "/socket.io",
    cors: {
      origin: "*",
      methods: ["GET", "POST"],
      credentials: true
    },
    transports: ["websocket", "polling"],
    pingTimeout: 20000,
    pingInterval: 25000
  });

  io.on("connection", (socket) => {
    console.log(`[Socket.IO] Twin client connected: ${socket.id}`);

    // 1. Topic Subscription
    socket.on("subscribe", (data) => {
      if (!data || !data.siteName) return;
      const room = `site:${data.siteName}`;
      socket.join(room);
      console.log(`[Socket.IO] Client ${socket.id} subscribed to: ${room}`);

      socket.emit("subscribed", {
        status: "ACTIVE",
        topic: room,
        timestamp: new Date().toISOString()
      });
    });

    // 2. Unsubscribe
    socket.on("unsubscribe", (data) => {
      if (!data || !data.siteName) return;
      const room = `site:${data.siteName}`;
      socket.leave(room);
      socket.emit("unsubscribed", { topic: room });
    });

    // 3. Two-way Incident Acknowledgement
    socket.on("acknowledge_incident", async (data) => {
      console.log(`[Socket.IO] Incident ack request:`, data);
      // Optional: await updateIncidentStatus(data.incidentId, 'acknowledged');
      
      io.to(`site:${data.siteName}`).emit("incident:updated", {
        incidentNumber: data.incidentId,
        site: data.siteName,
        status: "acknowledged",
        updatedAt: new Date().toISOString()
      });
    });

    socket.on("disconnect", (reason) => {
      console.log(`[Socket.IO] Client ${socket.id} disconnected: ${reason}`);
    });
  });

  // Helper method: Call this from /api/incidents/monitor controller
  io.publishIncident = function(incident) {
    if (!incident || !incident.site) return;
    const room = `site:${incident.site}`;
    io.to(room).emit("incident:new", incident);
    console.log(`[Socket.IO] Broadcasted incident ${incident.incidentNumber || incident.incidentType} to ${room}`);
  };

  return io;
}

module.exports = { initDigitalTwinSocket };
```

### Hooking into `/api/incidents/monitor`:
Inside your existing incident creation endpoint:
```javascript
// POST /api/incidents/monitor
app.post('/api/incidents/monitor', async (req, res) => {
  const newIncident = await saveIncidentToDatabase(req.body);
  
  // Broadcast to subscribed Digital Twins immediately:
  if (io && io.publishIncident) {
    io.publishIncident(newIncident);
  }

  return res.status(200).json({ success: true, incident: newIncident });
});
```

---

## 7. How the Upstream Team Can Test & Verify

### Step 1: Test Socket.IO Polling Handshake
```cmd
curl.exe -i "http://localhost:13000/socket.io/?EIO=4&transport=polling"
```
**Expected:** `HTTP 200 OK` returning `0{"sid":"...","upgrades":["websocket"]...}`.

### Step 2: Test WebSocket Upgrade Handshake
```cmd
curl.exe -i --max-time 3 -N -H "Connection: Upgrade" -H "Upgrade: websocket" -H "Sec-WebSocket-Version: 13" -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" "http://localhost:13000/socket.io/?EIO=4&transport=websocket"
```
**Expected:** `HTTP 101 Switching Protocols`.

### Step 3: Test End-to-End Through Kong Gateway
```cmd
curl.exe -i --max-time 3 -N -H "Connection: Upgrade" -H "Upgrade: websocket" -H "Sec-WebSocket-Version: 13" -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" "http://localhost:8088/socket.io/?EIO=4&transport=websocket"
```
**Expected:** `HTTP 101 Switching Protocols` with `Server: kong/3.9.3`.
