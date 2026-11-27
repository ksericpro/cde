# CDE Message Queue (Eclipse Mosquitto + Cedalo Management Center)

Lightweight, 100% open-source MQTT broker with a Web UI for managing per-topic client credentials and ACLs, designed to publish CDE data to external clients over **Cloudflare Tunnel (`wss://`)**.

---

## Architecture

```text
[ Internal CDE Publishers ]         [ External Interested Clients ]
  (n8n / Python / Go)                 (Web / Mobile / Scripts)
           │                                      │
   mqtt://cde-mosquitto:1883            wss://mqtt.yourdomain.com:443
    (Docker: cde-network)                         │
           │                             [ Cloudflare Tunnel ]
           ▼                                      │  (HTTP/WS proxy)
   ┌──────────────────────────────────────────────▼─────────┐
   │  cde-mosquitto (Eclipse Mosquitto 2 + Dynamic Security)│
   │   • :1883 (TCP MQTT)                                   │
   │   • :9001 (WebSockets → host :9002)                    │
   └─────────────────────────▲──────────────────────────────┘
                             │ Dynamic Security ($CONTROL)
   ┌─────────────────────────┴──────────────────────────────┐
   │  cde-mq-ui (Cedalo Management Center 2.6.4)            │
   │   • Web UI: http://localhost:8089                      │
   └────────────────────────────────────────────────────────┘
```

---

## Port Allocation

Host ports are chosen to avoid conflicts with other CDE services (`apigw` Kong uses `:8088`, `datamart` MinIO Console uses `:9001`):

| Service | Container Port | Default Host Port | Purpose |
| :--- | :---: | :---: | :--- |
| `cde-mosquitto` | `1883` | `1883` | Internal MQTT TCP (for `n8n`, CDE services, LAN) |
| `cde-mosquitto` | `9001` | `9002` | MQTT over WebSockets (**Cloudflare Tunnel target**) |
| `cde-mq-ui` | `8088` | `8089` | Cedalo Management Center Web UI (admin only) |

---

## Quick Start

1. **(Optional) Customize credentials and ports:**
   ```bash
   cd /opt/cde/MQ
   cp .env.example .env
   # Edit .env and change MQTT_ADMIN_PASSWORD, MQTT_PUBLISHER_PASSWORD, MMC_ADMIN_PASSWORD
   ```

2. **Initialize Dynamic Security & start the stack:**
   - **Linux / macOS (Bash):**
     ```bash
     chmod +x scripts/deploy_mq.sh scripts/verify_mq.sh
     ./scripts/deploy_mq.sh
     ```
   - **Windows (PowerShell):**
     ```powershell
     .\scripts\deploy_mq.ps1
     ```
   On first run, the deploy script will:
   - Create `cde-network` if it doesn't exist yet.
   - Generate `mosquitto/data/dynamic-security.json` with your admin user.
   - Set **Default ACLs to Deny** (no client can read/write any topic unless explicitly allowed).
   - Create an internal `cde-publisher` account allowed to publish to `cde/#`.
   - Start both `cde-mosquitto` and `cde-mq-ui`.

3. **Verify the deployment:**
   - **Linux / macOS:** `./scripts/verify_mq.sh`
   - **Windows (PowerShell):** `.\scripts\verify_mq.ps1`

---

## Managing Per-Topic Usernames & Passwords in Cedalo UI

> **Login note:** Use **`MMC_ADMIN_USER` / `MMC_ADMIN_PASSWORD`** from `.env` (default: `admin` / `cdepassword123`) to sign into the Cedalo Web UI. The `MQTT_ADMIN_USER` (`cedalo`) credential is only used internally by Cedalo to administer Mosquitto.
>
> **How MQTT topics work:** Unlike RabbitMQ queues, MQTT topics do **not** need to be pre-created — they exist automatically as soon as a client publishes or subscribes. Access per topic is controlled via **Roles (ACLs)** assigned to **Clients (username + password)**.

1. Open **`http://<host>:8089`** and sign in with `admin` / `<MMC_ADMIN_PASSWORD>`.
2. **Create a Role for the topic:**
   - Left sidebar → **Roles** → **New Role** → name it `role-alarms-read` → **Save**.
   - Click `role-alarms-read` → open the **ACLs** tab → **Add Row**:
     - **ACL Type:** `subscribePattern` *(for wildcards like `cde/alarms/#`)* or `subscribeLiteral` *(for an exact topic)*
     - **Topic:** `cde/alarms/#`
     - **Allow:** enabled (`true`)
   - Click **Save**.
3. **Create a Client (username + password):**
   - Left sidebar → **Clients** → **New Client**:
     - **Username:** `client_alarms`
     - **Password:** `alarmpass123` *(use a strong password in production)*
     - Click **Save**.
   - Click `client_alarms` → under **Roles**, assign `role-alarms-read` → **Save**.
4. Changes take effect **immediately** (no broker restart required) and persist in `mosquitto/data/dynamic-security.json`.

> **Tip:** Because default ACLs are set to `publishClientSend=deny` and `subscribe=deny`, `client_alarms` can *only* subscribe to `cde/alarms/#` and cannot publish or read any other topic.

---

## Manual Pub/Sub Verification

### 1. Test Subscribe & Publish (TCP — Zero Extra Tools Needed)

Open **two terminals** (works in both Bash and PowerShell):

**Terminal 1 — Subscribe as `client_alarms`:**
```bash
docker exec -it cde-mosquitto mosquitto_sub -h localhost -p 1883 -u client_alarms -P alarmpass123 -t "cde/alarms/#" -v
```

**Terminal 2 — Publish using the built-in `cde-publisher` account (from `.env`):**
```bash
docker exec cde-mosquitto mosquitto_pub -h localhost -p 1883 -u cde-publisher -P cdepublisher123 -t "cde/alarms/critical" -m '{"severity":"CRITICAL","msg":"door forced open"}'
```

Expected output in Terminal 1:
```text
cde/alarms/critical {"severity":"CRITICAL","msg":"door forced open"}
```

### 2. Verify Topic Isolation (Negative Tests)

- **Subscribing to an unauthorized topic is denied:**
  ```bash
  docker exec cde-mosquitto mosquitto_sub -h localhost -p 1883 -u client_alarms -P alarmpass123 -t "cde/other/#" -W 2 -d
  ```
  *(Expected: `SUBACK` returns reason code `135` / `Not authorized` or `0x80` failure, and no messages are received.)*

- **Subscriber cannot publish:**
  ```bash
  docker exec cde-mosquitto mosquitto_pub -h localhost -p 1883 -u client_alarms -P alarmpass123 -t "cde/alarms/test" -m "should-fail" -d
  ```
  *(Expected: publish is denied/dropped because `role-alarms-read` has no `publishClientSend` ACL.)*

### 3. Test with `scripts/test_pubsub.py` (Local WS or Cloudflare Tunnel WSS)

A ready-to-run Python CLI is provided at [`scripts/test_pubsub.py`](scripts/test_pubsub.py) (requires `pip install paho-mqtt`). It supports local TCP (`1883`), local WebSockets (`9002`), and Cloudflare Tunnel (`wss://...:443`).

- **Subscribe locally over WebSockets (`ws://127.0.0.1:9002`):**
  ```bash
  python3 scripts/test_pubsub.py sub -u client_alarms -p alarmpass123 -t "cde/alarms/#"
  ```
- **Subscribe through Cloudflare Tunnel (`wss://mqtt.yourdomain.com:443`):**
  ```bash
  python3 scripts/test_pubsub.py sub --host mqtt.yourdomain.com --tls -u client_alarms -p alarmpass123 -t "cde/alarms/#"
  ```
- **Publish locally over TCP (`mqtt://127.0.0.1:1883`):**
  ```bash
  python3 scripts/test_pubsub.py pub -u cde-publisher -p cdepublisher123 -t "cde/alarms/critical" -m '{"severity":"CRITICAL","msg":"door forced open"}'
  ```
- **Publish through Cloudflare Tunnel (`wss://mqtt.yourdomain.com:443`):**
  ```bash
  python3 scripts/test_pubsub.py pub --host mqtt.yourdomain.com --transport websockets --tls -u cde-publisher -p cdepublisher123 -t "cde/alarms/critical" -m "hello"
  ```

---

## Cloudflare Tunnel Setup (`wss://`)

Standard Cloudflare Tunnels proxy HTTP/WebSockets on port 443 natively (no `cloudflared` client needed on subscribers).

### Option A: Cloudflare Zero Trust Dashboard (Public Hostname)
Add a Public Hostname under your tunnel:
- **Subdomain / Domain:** `mqtt.yourdomain.com`
- **Service Type:** `HTTP`
- **URL:** `localhost:9002` *(or `cde-mosquitto:9001` if `cloudflared` runs inside `cde-network`)*

### Option B: `cloudflared` `config.yml`
```yaml
ingress:
  - hostname: mqtt.yourdomain.com
    service: http://localhost:9002
  - service: http_status:404
```

> **Important:** Do **not** expose `cde-mq-ui` (`:8089`) publicly unless protected behind **Cloudflare Access** (Zero Trust authentication) or kept LAN/VPN-only.

### Client Connection Example (Over Cloudflare Tunnel)
Always set **keepalive to 30–60 seconds** so Cloudflare's ~100s idle timeout doesn't drop quiet WebSocket connections.

**JavaScript / Node.js (`mqtt.js`):**
```js
import mqtt from "mqtt";

const client = mqtt.connect("wss://mqtt.yourdomain.com:443", {
  username: "client_alarms",
  password: "your-password",
  keepalive: 45,
  reconnectPeriod: 3000,
});

client.on("connect", () => {
  client.subscribe("cde/alarms/#");
});

client.on("message", (topic, payload) => {
  console.log(topic, payload.toString());
});
```

**Python (`paho-mqtt`):**
```python
import paho.mqtt.client as mqtt

client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, transport="websockets")
client.tls_set()
client.username_pw_set("client_alarms", "your-password")
client.on_connect = lambda c, u, f, rc, p: c.subscribe("cde/alarms/#")
client.on_message = lambda c, u, msg: print(msg.topic, msg.payload.decode())

client.connect("mqtt.yourdomain.com", 443, keepalive=45)
client.loop_forever()
```

---

## Publishing from `n8n` (Internal CDE Network)

Since both `n8n` and `cde-mosquitto` share `cde-network`, configure the built-in **n8n MQTT credential** as:
- **Protocol:** `mqtt`
- **Host:** `cde-mosquitto`
- **Port:** `1883`
- **Username:** `cde-publisher` (from `.env`)
- **Password:** `<MQTT_PUBLISHER_PASSWORD>`

Then use the **MQTT node** to publish payloads to topics like `cde/alarms/critical` or `cde/telemetry/sensor-01`.
