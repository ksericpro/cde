const http = require('http');
const crypto = require('crypto');

// Parse CLI flags and arguments
const args = process.argv.slice(2);
const isContinuous = args.includes('--listen') || args.includes('-l') || args.includes('--watch');
const rawTarget = args.find(a => !a.startsWith('-'));
let targetHost = process.env.KONG_HOST || 'localhost';
let targetPort = parseInt(process.env.KONG_PORT || '8088', 10);
let targetPath = process.env.WS_PATH || '/socket.io/?EIO=4&transport=websocket';

if (rawTarget) {
  if (/^(wss?|https?):\/\//i.test(rawTarget)) {
    try {
      const parsedUrl = new URL(rawTarget.replace(/^ws(s)?:/i, 'http$1:'));
      targetHost = parsedUrl.hostname;
      if (parsedUrl.port) {
        targetPort = parseInt(parsedUrl.port, 10);
      } else {
        targetPort = parsedUrl.protocol === 'https:' ? 443 : 80;
      }
      targetPath = (parsedUrl.pathname || '/') + (parsedUrl.search || '');
    } catch {
      targetPath = rawTarget;
    }
  } else {
    targetPath = rawTarget;
  }
}

const CONFIG = {
  host: targetHost,
  port: targetPort,
  path: targetPath,
  apiKey: process.env.API_KEY || 'vizzio-digital-twin-key-2026',
  timeoutMs: isContinuous ? 0 : 10000
};

console.log('='.repeat(62));
console.log('  Digital Twin Real-Time WebSocket Client Connector');
console.log('='.repeat(62));
console.log(`Target:     ws://${CONFIG.host}:${CONFIG.port}${CONFIG.path}`);
console.log(`API Key:    ${CONFIG.apiKey}`);
console.log(`Mode:       ${isContinuous ? 'Continuous Streaming (Ctrl+C to stop)' : 'Handshake Verification'}`);
console.log('-'.repeat(62));

// Masking helper for sending client -> server RFC 6455 WebSocket frames
function createWsTextFrame(text) {
  const payload = Buffer.from(text, 'utf8');
  const maskKey = crypto.randomBytes(4);
  let frame;

  if (payload.length <= 125) {
    frame = Buffer.alloc(2 + 4 + payload.length);
    frame[0] = 0x81; // FIN + text opcode
    frame[1] = 0x80 | payload.length; // MASK bit set + len
    maskKey.copy(frame, 2);
    for (let i = 0; i < payload.length; i++) {
      frame[6 + i] = payload[i] ^ maskKey[i % 4];
    }
  } else if (payload.length <= 65535) {
    frame = Buffer.alloc(4 + 4 + payload.length);
    frame[0] = 0x81;
    frame[1] = 0x80 | 126;
    frame.writeUInt16BE(payload.length, 2);
    maskKey.copy(frame, 4);
    for (let i = 0; i < payload.length; i++) {
      frame[8 + i] = payload[i] ^ maskKey[i % 4];
    }
  }
  return frame;
}

const secWebSocketKey = crypto.randomBytes(16).toString('base64');

const req = http.request({
  host: CONFIG.host,
  port: CONFIG.port,
  path: CONFIG.path,
  headers: {
    'Connection': 'Upgrade',
    'Upgrade': 'websocket',
    'Sec-WebSocket-Key': secWebSocketKey,
    'Sec-WebSocket-Version': '13',
    'apikey': CONFIG.apiKey
  }
});

let isUpgraded = false;
let finished = false;

req.on('upgrade', (res, socket, head) => {
  isUpgraded = true;
  console.log('\n[1] Protocol Upgrade Success:');
  console.log(`    Status:           ${res.statusCode} ${res.statusMessage}`);
  console.log(`    Kong Gateway:     ${res.headers['server'] || 'N/A'}`);
  console.log(`    Via:              ${res.headers['via'] || 'N/A'}`);
  console.log(`    Upstream Latency: ${res.headers['x-kong-upstream-latency'] || 'N/A'} ms`);
  console.log(`    Proxy Latency:    ${res.headers['x-kong-proxy-latency'] || 'N/A'} ms`);
  console.log('-'.repeat(62));

  function sendText(str) {
    const frame = createWsTextFrame(str);
    socket.write(frame);
  }

  let rxBuffer = Buffer.alloc(0);

  function decodeFrames(chunk) {
    rxBuffer = Buffer.concat([rxBuffer, chunk]);
    const frames = [];

    while (rxBuffer.length >= 2) {
      const firstByte = rxBuffer[0];
      const opcode = firstByte & 0x0f;
      const secondByte = rxBuffer[1];
      const isMasked = (secondByte & 0x80) === 0x80;
      let payloadLen = secondByte & 0x7f;
      let headerLen = 2;

      if (payloadLen === 126) {
        if (rxBuffer.length < 4) break;
        payloadLen = rxBuffer.readUInt16BE(2);
        headerLen = 4;
      } else if (payloadLen === 127) {
        if (rxBuffer.length < 10) break;
        payloadLen = Number(rxBuffer.readBigUInt64BE(2));
        headerLen = 10;
      }

      if (isMasked) {
        headerLen += 4;
      }

      if (rxBuffer.length < headerLen + payloadLen) {
        break; // Incomplete frame
      }

      let payload = rxBuffer.slice(headerLen, headerLen + payloadLen);
      if (isMasked) {
        const maskKey = rxBuffer.slice(headerLen - 4, headerLen);
        payload = Buffer.from(payload);
        for (let i = 0; i < payload.length; i++) {
          payload[i] ^= maskKey[i % 4];
        }
      }

      frames.push({ opcode, payload, text: payload.toString('utf8') });
      rxBuffer = rxBuffer.slice(headerLen + payloadLen);
    }

    return frames;
  }

  function handleMessage(raw) {
    // 1. Socket.IO Namespace Connect ACK (packet 40 / 40{...})
    if (raw.startsWith('40') || raw.includes('40{')) {
      console.log('    ✅ Socket.IO Namespace Connected! (packet 40 ack received)');
      
      // Subscribe to site
      console.log('\n[4] Subscribing to Site Room: site:SOV @ 38ALT (packet 42)...');
      sendText('42["subscribe",{"siteName":"SOV @ 38ALT"}]');

      if (!isContinuous && !finished) {
        finished = true;
        setTimeout(() => {
          console.log('\n✅ Verification Complete: Handshake, Session, and Topic Subscription OK.');
          console.log('   (Run with --listen to keep the streaming connection active)');
          socket.destroy();
          process.exit(0);
        }, 1200);
      }
      return;
    }

    // 2. Engine.IO Session Handshake (packet 0{...})
    if (raw.startsWith('0') || raw.includes('pingInterval')) {
      const jsonStart = raw.indexOf('{');
      const jsonEnd = raw.lastIndexOf('}');
      if (jsonStart !== -1 && jsonEnd !== -1) {
        try {
          const handshake = JSON.parse(raw.substring(jsonStart, jsonEnd + 1));
          console.log('\n[2] Engine.IO Session Handshake Confirmed:');
          console.log(`    Session ID:       ${handshake.sid}`);
          console.log(`    Ping Interval:    ${handshake.pingInterval} ms`);
          console.log(`    Ping Timeout:     ${handshake.pingTimeout} ms`);

          // Send Socket.IO namespace connect (40)
          console.log('\n[3] Handshake Step 2: Connecting to Socket.IO Namespace (packet 40)...');
          sendText('40');
          return;
        } catch {
          // fall through
        }
      }
    }

    // 3. Engine.IO Ping (2) -> Client Pong (3)
    if (raw === '2' || (raw.startsWith('2') && raw.length < 5)) {
      console.log('💓 Received Server Heartbeat Ping (2) -> Responding Pong (3)');
      sendText('3');
      return;
    }

    // 4. Engine.IO Pong (3)
    if (raw === '3' || (raw.startsWith('3') && raw.length < 5)) {
      console.log('💓 Received Server Heartbeat Pong (3)');
      return;
    }

    // 5. Socket.IO Event / Incident frame
    if (raw.startsWith('42') || raw.includes('42[')) {
      console.log('\n⚡ [Real-Time Incident Stream Event]:');
      console.log(raw.replace(/^[^4]*/, ''));
      return;
    }

    // 6. Generic JSON / Native WebSocket frame (e.g. /ws)
    try {
      const parsed = JSON.parse(raw);
      console.log('\n📥 [Native WebSocket Message]:', JSON.stringify(parsed, null, 2));
      if (!isContinuous && !finished) {
        finished = true;
        setTimeout(() => {
          console.log('\n✅ Verification Complete: Native WebSocket communication verified.');
          socket.destroy();
          process.exit(0);
        }, 800);
      }
      return;
    } catch {
      // plain text
    }

    console.log('\n📥 [Frame Received]:', raw);
  }

  function handleData(buf) {
    const frames = decodeFrames(buf);
    for (const frame of frames) {
      if (frame.opcode === 0x08) {
        const code = frame.payload.length >= 2 ? frame.payload.readUInt16BE(0) : 1000;
        console.log(`\n🔌 Server sent Close Frame (code: ${code})`);
        socket.destroy();
        return;
      }
      if (frame.opcode === 0x09) {
        // RFC 6455 Ping -> Send Pong (opcode 0x0a)
        const pong = Buffer.alloc(2);
        pong[0] = 0x8a;
        pong[1] = 0x00;
        socket.write(pong);
        continue;
      }
      if (frame.opcode === 0x01 || frame.opcode === 0x02) {
        handleMessage(frame.text);
      }
    }
  }

  if (head && head.length > 0) {
    handleData(head);
  }

  socket.on('data', handleData);

  socket.on('close', (hadError) => {
    console.log(`\n🔌 WebSocket connection closed (hadError: ${hadError})`);
  });

  socket.on('error', (err) => {
    console.error('❌ Socket error:', err.message);
  });
});

req.on('response', (res) => {
  console.log(`\n⚠️ Gateway returned HTTP ${res.statusCode} without upgrade.`);
  let body = '';
  res.on('data', chunk => body += chunk);
  res.on('end', () => {
    console.log('Response body:', body);
    process.exit(1);
  });
});

req.on('error', (err) => {
  console.error('\n❌ Connection request failed:', err.message);
  process.exit(1);
});

if (CONFIG.timeoutMs > 0) {
  req.setTimeout(CONFIG.timeoutMs, () => {
    if (!isUpgraded) {
      console.error(`\n⌛ Connection timed out after ${CONFIG.timeoutMs}ms.`);
      req.destroy();
      process.exit(1);
    }
  });
}

req.end();
