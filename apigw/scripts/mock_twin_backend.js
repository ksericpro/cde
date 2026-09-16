/**
 * Standalone Mock Backend for Digital Twin Integration (REST + WebSocket)
 * Zero external dependencies - uses Node.js standard library (http, crypto).
 * 
 * Runs on port 3001 by default (or process.env.PORT).
 * 
 * Endpoints:
 *   - GET  /api/visualization/hierarchy
 *   - GET  /api/visualization/incidents
 *   - GET  /api/visualization/device-health
 *   - POST /api/auth/login
 *   - WS   /ws  (RFC 6455 Native WebSocket for 2-way twin communication)
 */

const http = require('http');
const crypto = require('crypto');

const PORT = process.env.PORT || 3001;

// In-memory state
let activeIncidents = [
  { id: 'INC-2026-101', title: 'Camera #1 Offline', zone: 'L4 Corridor War Room', severity: 'HIGH', status: 'PENDING', time: new Date().toISOString() },
  { id: 'INC-2026-102', title: 'Crowd Detection', zone: 'L4 ICC-1', severity: 'MEDIUM', status: 'ACKNOWLEDGED', time: new Date().toISOString() },
  { id: 'INC-2026-103', title: 'Loitering Alert', zone: 'L2 Reception Lobby', severity: 'LOW', status: 'RESOLVED', time: new Date().toISOString() }
];

let connectedSockets = new Set();

const server = http.createServer((req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  
  // CORS Headers
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization, apikey');

  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    res.end();
    return;
  }

  // REST: Auth Login
  if (url.pathname === '/api/auth/login' && req.method === 'POST') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      success: true,
      data: {
        token: 'mock-jwt-token-vizzio-' + Date.now(),
        refreshToken: 'mock-refresh-token',
        user: { email: 'vizzio@imops.local', role: 'super_admin' }
      }
    }));
    return;
  }

  // REST: Hierarchy
  if (url.pathname === '/api/visualization/hierarchy') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      success: true,
      data: {
        site: {
          _id: '6a8289d3e9b4269e23c744d2',
          name: url.searchParams.get('siteName') || 'SOV @ 38ALT',
          code: 'SOV_38ALT',
          status: 'active',
          location: { latitude: 1.27565, longitude: 103.79751 }
        },
        totalBuildings: 1,
        totalFloors: 6,
        totalZones: 13,
        floors: [
          { floorNumber: 1, name: 'Level 1 Lift Lobby', activeDevices: 4, alerts: 0 },
          { floorNumber: 2, name: 'Level 2 Reception', activeDevices: 6, alerts: 1 },
          { floorNumber: 3, name: 'Level 3 Offices', activeDevices: 8, alerts: 0 },
          { floorNumber: 4, name: 'Level 4 ICC War Room', activeDevices: 12, alerts: 2 },
          { floorNumber: 5, name: 'Level 5 Cyber Room', activeDevices: 7, alerts: 0 },
          { floorNumber: 6, name: 'Level 6 Rooftop', activeDevices: 3, alerts: 0 }
        ]
      }
    }));
    return;
  }

  // REST: Incidents
  if (url.pathname === '/api/visualization/incidents') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      success: true,
      data: {
        incidents: activeIncidents,
        totalCount: activeIncidents.length,
        pendingCount: activeIncidents.filter(i => i.status === 'PENDING').length
      }
    }));
    return;
  }

  // REST: Device Health
  if (url.pathname === '/api/visualization/device-health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      success: true,
      data: {
        totalCameras: 40,
        online: 38,
        offline: 2,
        healthPercentage: 95.0
      }
    }));
    return;
  }

  // 404
  res.writeHead(404, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ error: 'Endpoint not found', path: url.pathname }));
});

// -----------------------------------------------------------------------------
// RFC 6455 Native WebSocket Implementation (No external dependencies)
// -----------------------------------------------------------------------------
server.on('upgrade', (req, socket, head) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  
  if (url.pathname !== '/ws' && url.pathname !== '/ws/twin') {
    socket.destroy();
    return;
  }

  const secKey = req.headers['sec-websocket-key'];
  if (!secKey) {
    socket.destroy();
    return;
  }

  // Compute Accept hash
  const hash = crypto.createHash('sha1')
    .update(secKey + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11')
    .digest('base64');

  const headers = [
    'HTTP/1.1 101 Switching Protocols',
    'Upgrade: websocket',
    'Connection: Upgrade',
    `Sec-WebSocket-Accept: ${hash}`
  ];

  socket.write(headers.join('\r\n') + '\r\n\r\n');
  connectedSockets.add(socket);
  console.log(`[WS] Client connected. Total clients: ${connectedSockets.size}`);

  // Send initial welcome message
  sendWsMessage(socket, {
    type: 'WELCOME',
    message: 'Connected to iMOPS Twin Realtime Stream via Kong Gateway',
    timestamp: new Date().toISOString(),
    supportedCommands: ['SUBSCRIBE', 'ACKNOWLEDGE_INCIDENT', 'TRIGGER_INCIDENT', 'PING']
  });

  socket.on('data', (buffer) => {
    handleWsFrame(socket, buffer);
  });

  socket.on('close', () => {
    connectedSockets.delete(socket);
    console.log(`[WS] Client disconnected. Total clients: ${connectedSockets.size}`);
  });

  socket.on('error', (err) => {
    console.error('[WS Error]', err.message);
    connectedSockets.delete(socket);
  });
});

// Helper: send JSON frame
function sendWsMessage(socket, dataObj) {
  try {
    const payload = Buffer.from(JSON.stringify(dataObj), 'utf8');
    const length = payload.length;
    let header;

    if (length < 126) {
      header = Buffer.from([0x81, length]);
    } else if (length <= 65535) {
      header = Buffer.alloc(4);
      header[0] = 0x81;
      header[1] = 126;
      header.writeUInt16BE(length, 2);
    } else {
      header = Buffer.alloc(10);
      header[0] = 0x81;
      header[1] = 127;
      header.writeBigUInt64BE(BigInt(length), 2);
    }

    socket.write(Buffer.concat([header, payload]));
  } catch (e) {
    connectedSockets.delete(socket);
  }
}

// Broadcast to all connected Digital Twins
function broadcast(dataObj) {
  for (const sock of connectedSockets) {
    sendWsMessage(sock, dataObj);
  }
}

// Parse incoming WebSocket client frame (RFC 6455 unmasking)
function handleWsFrame(socket, buffer) {
  if (buffer.length < 2) return;
  const isMasked = (buffer[1] & 0x80) === 0x80;
  let payloadLen = buffer[1] & 0x7f;
  let offset = 2;

  if (payloadLen === 126) {
    payloadLen = buffer.readUInt16BE(2);
    offset = 4;
  } else if (payloadLen === 127) {
    payloadLen = Number(buffer.readBigUInt64BE(2));
    offset = 10;
  }

  let maskKey = null;
  if (isMasked) {
    maskKey = buffer.slice(offset, offset + 4);
    offset += 4;
  }

  const payload = buffer.slice(offset, offset + payloadLen);
  if (isMasked) {
    for (let i = 0; i < payload.length; i++) {
      payload[i] ^= maskKey[i % 4];
    }
  }

  const messageStr = payload.toString('utf8');
  try {
    const msg = JSON.parse(messageStr);
    console.log('[WS INCOMING]', msg);

    // 2-Way Command Dispatcher
    switch (msg.type || msg.action) {
      case 'PING':
        sendWsMessage(socket, { type: 'PONG', timestamp: new Date().toISOString() });
        break;

      case 'SUBSCRIBE':
        sendWsMessage(socket, {
          type: 'SUBSCRIBED',
          topic: msg.topic || 'site:SOV @ 38ALT',
          status: 'ACTIVE',
          message: `Subscribed to live events for ${msg.topic || 'SOV @ 38ALT'}`
        });
        break;

      case 'ACKNOWLEDGE_INCIDENT':
        const targetInc = activeIncidents.find(i => i.id === msg.incidentId);
        if (targetInc) {
          targetInc.status = 'ACKNOWLEDGED';
          targetInc.acknowledgedBy = msg.user || 'vizzio_operator';
          targetInc.ackTime = new Date().toISOString();
        }
        // Broadcast state update to all twins
        broadcast({
          type: 'INCIDENT_UPDATED',
          incidentId: msg.incidentId,
          status: 'ACKNOWLEDGED',
          user: msg.user || 'vizzio_operator',
          time: new Date().toISOString()
        });
        break;

      case 'TRIGGER_INCIDENT':
        const newInc = {
          id: 'INC-' + Date.now().toString().slice(-4),
          title: msg.title || 'Simulated Intrusion Alarm',
          zone: msg.zone || 'Level 4 ICC War Room',
          severity: msg.severity || 'CRITICAL',
          status: 'PENDING',
          time: new Date().toISOString()
        };
        activeIncidents.unshift(newInc);
        broadcast({
          type: 'INCIDENT_ALERT',
          incident: newInc,
          site: 'SOV @ 38ALT'
        });
        break;

      default:
        sendWsMessage(socket, { type: 'ECHO', received: msg });
        break;
    }
  } catch (err) {
    console.warn('[WS] Failed to parse message:', messageStr);
  }
}

// Background Simulated Incident Generator (every 12 seconds)
const demoAlerts = [
  { title: 'Motion Loitering Alert', zone: 'L2 Reception Lobby', severity: 'LOW' },
  { title: 'Camera #3 Offline - Loss of RTSP Signal', zone: 'L6 Rooftop West', severity: 'HIGH' },
  { title: 'Crowd Threshold Exceeded (>15 pax)', zone: 'L4 Corridor War Room', severity: 'MEDIUM' },
  { title: 'Door Contact Forced Open', zone: 'L5 Cyber Room Server Bay', severity: 'CRITICAL' }
];

let alertIdx = 0;
setInterval(() => {
  if (connectedSockets.size > 0) {
    const template = demoAlerts[alertIdx % demoAlerts.length];
    alertIdx++;
    const simIncident = {
      id: 'INC-' + Date.now().toString().slice(-4),
      title: template.title,
      zone: template.zone,
      severity: template.severity,
      status: 'PENDING',
      time: new Date().toISOString()
    };
    activeIncidents.unshift(simIncident);
    if (activeIncidents.length > 20) activeIncidents.pop();

    console.log(`[Push Alert] ${simIncident.title} -> ${connectedSockets.size} client(s)`);
    broadcast({
      type: 'INCIDENT_ALERT',
      incident: simIncident,
      site: 'SOV @ 38ALT'
    });
  }
}, 12000);

server.listen(PORT, () => {
  console.log(`====================================================`);
  console.log(`🚀 Mock Twin Upstream Server running on port ${PORT}`);
  console.log(`   REST API:   http://localhost:${PORT}/api/visualization/hierarchy`);
  console.log(`   WebSocket:  ws://localhost:${PORT}/ws`);
  console.log(`====================================================`);
});
