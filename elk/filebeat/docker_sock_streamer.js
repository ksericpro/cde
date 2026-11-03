/**
 * Real-time Docker Socket Log Streamer for ELK
 * Streams stdout/stderr from Docker Engine API (/var/run/docker.sock) in real time
 * into Elasticsearch — works automatically even when Docker Desktop uses the
 * binary "local" logging driver instead of "json-file".
 */
const http = require('http');
const crypto = require('crypto');

const ES_HOST = process.env.ES_HOST || 'elasticsearch';
const ES_PORT = parseInt(process.env.ES_PORT || '9200', 10);
const SOCKET_PATH = '/var/run/docker.sock';
const TARGET_PREFIXES = ['imops-', 'n8n-', 'kong-'];
const activeStreams = new Set();

function indexLogLine(containerName, rawLine) {
  if (!rawLine || !rawLine.trim()) return;
  if (rawLine.includes('[DEBUG] GET /api/health')) return;

  let ts = new Date().toISOString();
  let msg = rawLine.trim();

  const isoMatch = msg.match(/^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z)\s+(.*)$/);
  if (isoMatch) {
    ts = isoMatch[1];
    msg = isoMatch[2];
  }

  let logSource = 'cde-system';
  let indexPrefix = 'cde-system-logs';
  if (containerName.startsWith('imops-')) {
    logSource = 'imops-application';
    indexPrefix = 'cde-imops-logs';
  } else if (containerName.startsWith('n8n-')) {
    logSource = 'n8n-workflow-engine';
    indexPrefix = 'cde-n8n-logs';
  } else if (containerName.startsWith('kong-')) {
    logSource = 'kong-service';
    indexPrefix = 'cde-kong-logs';
  }

  const datePart = ts.slice(0, 10).replace(/-/g, '.');
  const indexName = `${indexPrefix}-${datePart}`;
  const isError = /\b(error|exception|fail|failed|fatal|400|401|403|404|500|502|503)\b/i.test(msg);
  const docId = crypto.createHash('sha1').update(`${containerName}:${ts}:${msg}`).digest('hex');

  const body = JSON.stringify({
    '@timestamp': ts,
    log_source: logSource,
    container: { name: containerName },
    service: { name: containerName },
    response: { status: isError ? 500 : 200 },
    message: msg,
  });

  const req = http.request({
    hostname: ES_HOST,
    port: ES_PORT,
    path: `/${indexName}/_doc/${docId}`,
    method: 'PUT',
    headers: {
      'Content-Type': 'application/json',
      'Content-Length': Buffer.byteLength(body),
    },
  }, (res) => {
    res.resume();
  });
  req.on('error', () => {});
  req.write(body);
  req.end();
}

function attachContainerStream(containerId, containerName) {
  if (activeStreams.has(containerId)) return;
  activeStreams.add(containerId);
  const sinceSec = Math.floor(Date.now() / 1000) - 60;

  const req = http.request({
    socketPath: SOCKET_PATH,
    path: `/containers/${containerId}/logs?follow=1&stdout=1&stderr=1&timestamps=1&since=${sinceSec}`,
    method: 'GET',
  }, (res) => {
    console.log(`[+] Streaming live logs from container: ${containerName}`);
    let remainder = '';
    res.on('data', (chunk) => {
      // Strip Docker multiplexed stream 8-byte header bytes if present, keep printable UTF-8 + newlines
      const text = remainder + chunk.toString('utf8').replace(/[\x00-\x08\x0B\x0C\x0E-\x1F]/g, '');
      const lines = text.split(/\r?\n/);
      remainder = lines.pop() || '';
      for (const line of lines) {
        const cleaned = line.replace(/^.*?(?=\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})/, '');
        indexLogLine(containerName, cleaned);
      }
    });
    res.on('end', () => {
      activeStreams.delete(containerId);
    });
    res.on('error', () => {
      activeStreams.delete(containerId);
    });
  });

  req.on('error', () => {
    activeStreams.delete(containerId);
  });
  req.end();
}

function discoverContainers() {
  const req = http.request({
    socketPath: SOCKET_PATH,
    path: '/containers/json',
    method: 'GET',
  }, (res) => {
    let data = '';
    res.on('data', (c) => (data += c));
    res.on('end', () => {
      try {
        const list = JSON.parse(data);
        for (const c of list) {
          const name = ((c.Names && c.Names[0]) || '').replace(/^\//, '');
          if (TARGET_PREFIXES.some((p) => name.startsWith(p))) {
            attachContainerStream(c.Id, name);
          }
        }
      } catch (e) {}
    });
  });
  req.on('error', () => {});
  req.end();
}

console.log('[*] Starting real-time Docker Socket Log Streamer for ELK...');
discoverContainers();
setInterval(discoverContainers, 10000);

