const http = require('http');
const crypto = require('crypto');

// Parse CLI flags and arguments
const args = process.argv.slice(2);
const isContinuous = args.includes('--listen') || args.includes('-l') || args.includes('--watch');
const customPath = args.find(a => !a.startsWith('-'));

const CONFIG = {
  host: process.env.KONG_HOST || 'localhost',
  port: parseInt(process.env.KONG_PORT || '8088', 10),
  path: customPath || process.env.WS_PATH || '/socket.io/?EIO=4&transport=websocket',
  apiKey: process.env.API_KEY || 'vizzio-digital-twin-key-2026',
  timeoutMs: isContinuous ? 0 : 10000
};

console.log('='.repeat(62));
console.log('  Digital Twin Real-Time WebSocket Client Connector');
console.log('='.repeat(62));
console.log(`Target:     http://${CONFIG.host}:${CONFIG.port}${CONFIG.path}`);
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

  function handleData(buf) {
    const raw = buf.toString('utf8');
    
    // Engine.IO handshake
    if (raw.includes('{"sid":')) {
      const jsonStart = raw.indexOf('{');
      const jsonEnd = raw.lastIndexOf('}');
      if (jsonStart !== -1 && jsonEnd !== -1) {
        const handshake = JSON.parse(raw.substring(jsonStart, jsonEnd + 1));
        console.log('\n[2] Engine.IO Session Handshake Confirmed:');
        console.log(`    Session ID:       ${handshake.sid}`);
        console.log(`    Ping Interval:    ${handshake.pingInterval} ms`);
        console.log(`    Ping Timeout:     ${handshake.pingTimeout} ms`);

        // Send Socket.IO namespace connect (40)
        console.log('\n[3] Handshake Step 2: Connecting to Socket.IO Namespace (packet 40)...');
        sendText('40');
      }
      return;
    }

    // Socket.IO namespace connect ACK
    if (raw.includes('40{')) {
      console.log('    Socket.IO Namespace Connected! (packet 40 ack received)');
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

    // Server Ping (2) -> Client Pong (3)
    if (raw.includes('2') && raw.length < 5) {
      console.log('💓 Received Server Heartbeat Ping (2) -> Responding Pong (3)');
      sendText('3');
      return;
    }

    // Server Pong
    if (raw.includes('3') && raw.length < 5) {
      console.log('💓 Received Server Heartbeat Pong (3)');
      return;
    }

    // Incident / Event frame
    if (raw.includes('42[')) {
      console.log('\n⚡ [Real-Time Incident Stream Event]:');
      console.log(raw.replace(/^[^4]*/, ''));
      return;
    }

    // Raw/Generic frame
    console.log('\n📥 [Frame Received]:', raw);
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
