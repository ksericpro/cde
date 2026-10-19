# Kong Gateway WAF Rate Limiting & Penalty Lockout Implementation

This document details the architecture, configuration, and operational procedures for the **WAF-style Rate Limiting & Temporary IP Lockout (Penalty Box)** implemented on the Proscalar Webhook Ingress (`POST /api/proscalar/webhook` -> `imops-proscalar-n8n-service`).

---

### 1. Architectural Overview & Policy Rules

Standard API gateway rate limiting (such as Kong's native `rate-limiting` plugin) uses fixed or sliding counter windows. When a client violates the threshold, requests return `HTTP 429`, but the client can resume sending requests the instant the window rolls over.

In contrast, this **WAF-style Rate Limiter** enforces a **Lockout Jail (Penalty Box)**:
1. **Burst Threshold Tracking:** Evaluates client requests using atomic Redis operations within a sliding window (**30 requests per 10-second window**).
2. **Penalty Enforcement:** If the burst threshold is violated, the client's IP is immediately jailed for a penalty duration (**60 seconds**).
3. **Edge Rejection:** Subsequent requests from the banned IP are rejected at the gateway edge (`HTTP 429 Too Many Requests`) with an active `Retry-After` countdown, **without touching upstream services (n8n or backend)**.
4. **Alarm & Life-Safety Fail-Open:** Because Proscalar ingests critical building alarms (fire, tamper, door security), Redis connectivity has a fast 100ms timeout and **fails open** if Redis is unreachable to avoid dropping emergency alerts.

### 1.1 Enforced Policy Parameters

| Parameter | Value | Description |
| :--- | :---: | :--- |
| **Target Ingress Route** | `POST /api/proscalar/webhook` | Attached to service `imops-proscalar-n8n-service` |
| **Tracking Identity** | Client IP (`X-Forwarded-For`) | Extracts real caller IP via Kong's `trusted_ips` configuration |
| **Burst Window** | **`10 seconds`** | Window tracked in Redis key `waf:rate:<ip>` |
| **Burst Ceiling** | **`30 requests`** | Safe for multi-zone alarms & badge scans; blocks abusive spikes |
| **Lockout Jail Duration** | **`60 seconds`** | Temporary ban TTL stored in Redis key `waf:ban:<ip>` |
| **Fail-Safe Socket Timeout** | **`100 ms`** | Fail-fast socket; fails open if Redis is down |
| **Secondary Quota Guard** | **`120 req / min`** | Native Kong `rate-limiting` plugin enforcing a sustained ceiling |

### 1.2 Enforcement Lifecycle

```
Incoming Request (POST /api/proscalar/webhook)
  │
  ├─► [Step 1: Check Lockout Jail]
  │     Query Redis: "waf:ban:<ip>"
  │     ├── IF BANNED:
  │     │   └─► REJECT AT EDGE (HTTP 429 Too Many Requests)
  │     │       Header: "Retry-After: <remaining_ttl>"
  │     │       Header: "X-WAF-Status: Blocked"
  │     │       (Backend n8n is never touched)
  │     │
  │     └── IF NOT BANNED: Proceed to Step 2
  │
  ├─► [Step 2: Atomic Burst Counter]
  │     Increment counter: "waf:rate:<ip>" (TTL: 10s)
  │     ├── IF COUNT > 30 (Burst Limit Exceeded):
  │     │   └─► TRIGGER LOCKOUT JAIL
  │     │       Set Redis: "waf:ban:<ip>" with TTL = 60s
  │     │       Delete: "waf:rate:<ip>"
  │     │       Return HTTP 429 Too Many Requests
  │     │       Header: "Retry-After: 60"
  │     │       Header: "X-WAF-Status: Penalized"
  │     │
  │     └── IF COUNT <= 30 (Normal Traffic):
  │         └─► ALLOW THROUGH
  │             Forward request to n8n upstream (HTTP 200 OK)
```

### 1.3 Lockout Response Example

```http
HTTP/1.1 429 Too Many Requests
Content-Type: application/json
Retry-After: 54
X-WAF-Status: Blocked

{
  "error": "Too Many Requests",
  "message": "WAF: Client locked out due to anomalous burst. Try again in 54 seconds.",
  "retry_after": 54
}
```

---

## 2. Infrastructure Components

### 2.1 Redis Service (`docker-compose.yml`)
A dedicated lightweight Redis container (`kong-redis`) runs in `apigw/docker-compose.yml` on the shared internal Docker network:

```yaml
  kong-redis:
    image: redis:7-alpine
    container_name: kong-redis
    command: redis-server --appendonly yes --maxmemory 128mb --maxmemory-policy allkeys-lru
    volumes:
      - redisdata:/data
    ports:
      - "6380:6379"
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 3s
      retries: 5
    networks:
      - default
      - cde-network
    restart: unless-stopped
```

### 2.2 Real Client IP Detection
To prevent Docker NAT bridge or reverse proxies from masking real client IPs (which would cause entire subnets to be jailed together), Kong is configured with:

```yaml
      KONG_REAL_IP_HEADER: X-Forwarded-For
      KONG_TRUSTED_IPS: 0.0.0.0/0,::/0
      # Allow resty.redis inside Kong's Lua sandbox
      KONG_UNTRUSTED_LUA_SANDBOX_REQUIRES: resty.redis
```

---

## 3. Lua Script: `waf_proscalar_ratelimit.lua`

The core WAF logic is maintained in [waf_proscalar_ratelimit.lua](file:///c:/Projects/cde/apigw/scripts/waf_proscalar_ratelimit.lua):

* **Fail-Fast Socket:** `red:set_timeout(100)` prevents slow Redis lookups from stalling webhook ingress.
* **Fail-Open Safety:** Returns cleanly on connection errors so legitimate alarms pass through.
* **Atomic INCR + EXPIRE:** Uses Redis `EVAL` to avoid race conditions during concurrent bursts.
* **Response Headers:** Injects `X-WAF-Status: Penalized` (upon initial ban) and `X-WAF-Status: Blocked` (during active lockout) along with standard `Retry-After`.

---

## 4. Automated Provisioning

Deploying the service, routes, credentials, and WAF plugin is fully automated:

### Windows (PowerShell)
```powershell
cd c:\Projects\cde\apigw
.\scripts\setup_proscalar_n8n.ps1
```

### Linux (Bash)
```bash
cd /opt/cde/apigw
bash ./scripts/setup_proscalar_n8n.sh
```

The script automatically attaches or updates the `pre-function` plugin on `imops-proscalar-n8n-service`.

---

## 5. Operational Commands & Emergency Unban

### View Active Lockouts
To see all currently banned client IPs and their remaining penalty countdown:

* **PowerShell:**
  ```powershell
  .\scripts\get_banned_ips.ps1
  ```
* **Bash:**
  ```bash
  bash ./scripts/get_banned_ips.sh
  ```

### Manually Unban an IP Address
If an IP was locked out by accident or after incident triage:

* **PowerShell:**
  ```powershell
  .\scripts\unban_ip.ps1 -IpAddress "192.168.1.100"
  ```
* **Bash:**
  ```bash
  bash ./scripts/unban_ip.sh "192.168.1.100"
  ```

---

## 6. End-to-End Verification

Run the automated test suite to verify authorization, alarm ingestion, and WAF rate limit & lockout enforcement:

```powershell
cd c:\Projects\cde\apigw
.\scripts\test_proscalar_n8n.ps1
```

**Test 5 Output:**
```
[Test 5/5] Testing Gateway Rate Limiting & WAF Lockout Policy...
   Sending rapid burst of requests (exceeding 30 req/10s threshold)...
✅ PASSED: WAF Lockout enforced after 31 requests (HTTP 429 Too Many Requests).
   WAF Details: X-WAF-Status = Penalized | Retry-After = 60 s
   Verifying immediate lockout enforcement on subsequent request... Blocked as expected (HTTP 429 Lockout Jail).
```

---

## 7. Updating an Existing Running Deployment

Follow these steps to roll out the WAF rate limiting update to a server where Kong is already running (e.g., local developer machine or remote Linux host `sov-webapp`).

### Step 1: Start `kong-redis` and Recreate `kong-gateway`

Update the running Docker stack so that Kong links with the new Redis container and loads the real-IP environment variables:

#### On Windows (PowerShell):
```powershell
cd c:\Projects\cde\apigw

# 1. Start kong-redis and update kong-gateway
docker compose up -d kong-redis kong

# 2. Confirm containers are healthy and running
docker compose ps
```

#### On Linux (`sov-webapp`):
```bash
cd /opt/cde/apigw

# 1. Pull latest repo changes
git pull origin main

# 2. Launch kong-redis and recreate kong-gateway
docker compose up -d kong-redis kong

# 3. Test Redis status & connectivity
docker exec kong-redis redis-cli ping
# (Should return: PONG)

# Or test TCP connectivity from inside Kong Gateway container:
docker exec kong-gateway bash -c "</dev/tcp/kong-redis/6379 && echo 'Redis reachable from Kong!'"
```

> [!NOTE]
> Database records in PostgreSQL (`kong-db`) are preserved in the persistent volume `pgdata`. Existing services, routes, consumers, and credentials will not be lost.

### Step 2: Apply the WAF Policy to the Service

The deployment scripts are idempotent. They will preserve your existing service and route configurations, attaching or updating only the WAF `pre-function` plugin:

* **Windows:**
  ```powershell
  cd c:\Projects\cde\apigw
  .\scripts\setup_proscalar_n8n.ps1
  ```

* **Linux:**
  ```bash
  cd /opt/cde/apigw
  bash ./scripts/setup_proscalar_n8n.sh
  ```

*(Alternative)* **Manual Apply via Kong Admin API (Direct `curl`):**
If you prefer to attach only the plugin without re-running the full setup script:
```bash
curl -i -X POST http://localhost:8001/services/imops-proscalar-n8n-service/plugins \
  -F "name=pre-function" \
  -F "config.access[]=@scripts/waf_proscalar_ratelimit.lua"
```

### Step 3: Run the Verification Suite

Validate normal throughput and WAF lockout enforcement:

* **Windows:**
  ```powershell
  .\scripts\test_proscalar_n8n.ps1
  ```
* **Linux:**
  ```bash
  bash ./scripts/test_proscalar_n8n.sh
  ```

### Step 4: Emergency Rollback (Disable WAF)

If you need to instantly disable the WAF without restarting any containers:

```bash
# 1. Find the pre-function plugin ID
PLUGIN_ID=$(curl -s http://localhost:8001/services/imops-proscalar-n8n-service/plugins | grep -B 2 -A 5 '"name":"pre-function"' | grep -o '"id":"[^"]*' | head -n1 | cut -d'"' -f4)

# 2. Delete the plugin
curl -X DELETE "http://localhost:8001/plugins/$PLUGIN_ID"
```
The gateway immediately reverts to standard rate limiting without traffic interruption.

