1. **Verify Redis Access and Kong Prerequisites:** Prerequisite.
   Ensure your Redis instance is reachable from your Kong Gateway nodes.

The Lua script uses OpenResty's built-in `resty.redis` library, which comes pre-installed in standard Kong distributions. Test network connectivity from inside your Kong container or host:

```bash
nc -zv 127.0.0.1 6379

```

_(Replace `127.0.0.1` and `6379` with your actual Redis host and port, such as a Docker service name or private IP)._

2. **Ensure Real Client IP Detection is Enabled:** Kong Configuration.
   If Kong sits behind a load balancer, reverse proxy, or Cloudflare, ensure Kong extracts the actual client IP rather than the proxy's IP.

In your `kong.conf` or environment variables, configure:

```ini
real_ip_header = X-Forwarded-For
trusted_ips = 0.0.0.0/0,::/0  # Or restrict to your upstream proxy CIDRs

```

3. **Prepare the Lua Script:** Logic Verification.
   Create the Lua snippet that handles connection pooling, lockout checks, 10-second burst tracking, and the 60-second penalty ban.

Save this logic to a file named `rate_limit_ban.lua` for easy deployment:

```lua
local redis = require "resty.redis"
local red = redis:new()
red:set_timeout(1000)

-- Configure your Redis connection details
local ok, err = red:connect("127.0.0.1", 6379)
if not ok then
  kong.log.err("Failed to connect to Redis: ", err)
  return
end

-- Optional: If Redis requires authentication
-- red:auth("your_redis_password")

local client_ip = kong.client.get_forwarded_ip() or kong.client.get_ip()
local ban_key = "ban:" .. client_ip
local rate_key = "rate:" .. client_ip

-- Step 1: Check if IP is currently under a 60s lockout
local banned, _ = red:get(ban_key)
if banned and banned ~= ngx.null then
  local ttl, _ = red:ttl(ban_key)
  red:set_keepalive(10000, 100)
  return kong.response.exit(429, {
    message = "Rate limit exceeded. Access blocked for " .. tostring(ttl) .. " seconds."
  }, {
    ["Retry-After"] = tostring(ttl),
    ["Content-Type"] = "application/json"
  })
end

-- Step 2: Increment counter for the 10-second window
local count, err = red:incr(rate_key)
if count == 1 then
  red:expire(rate_key, 10)
end

-- Step 3: Trigger 60-second lockout if requests exceed 2
if count > 2 then
  red:setex(ban_key, 60, "locked")
  red:del(rate_key)
  red:set_keepalive(10000, 100)
  return kong.response.exit(429, {
    message = "Rate limit exceeded. You are locked out for 60 seconds."
  }, {
    ["Retry-After"] = "60",
    ["Content-Type"] = "application/json"
  })
end

-- Step 4: Return Redis connection to OpenResty socket pool
red:set_keepalive(10000, 100)

```

4. **Attach the Plugin to Kong:** Deployment.
   Choose **Method 1** (Admin API) or **Method 2** (Declarative DB-less) depending on your setup.

**Method 1: Via Admin API (REST)**

```bash
curl -i -X POST http://localhost:8001/services/<YOUR_SERVICE_NAME>/plugins \
  -F "name=pre-function" \
  -F "config.access[]=@rate_limit_ban.lua"

```

_(To apply globally instead of per-service, omit `/services/<YOUR_SERVICE_NAME>` from the URL)._

**Method 2: Via Declarative YAML (`kong.yml` / decK)**

```yaml
_format_version: "3.0"

services:
  - name: my-service
    url: http://backend-api:8080
    routes:
      - name: my-route
        paths:
          - /
    plugins:
      - name: pre-function
        config:
          access:
            - |
              local redis = require "resty.redis"
              local red = redis:new()
              red:set_timeout(1000)

              local ok, err = red:connect("127.0.0.1", 6379)
              if not ok then
                kong.log.err("Failed to connect to Redis: ", err)
                return
              end

              local client_ip = kong.client.get_forwarded_ip() or kong.client.get_ip()
              local ban_key = "ban:" .. client_ip
              local rate_key = "rate:" .. client_ip

              local banned, _ = red:get(ban_key)
              if banned and banned ~= ngx.null then
                local ttl, _ = red:ttl(ban_key)
                red:set_keepalive(10000, 100)
                return kong.response.exit(429, {
                  message = "Rate limit exceeded. Access blocked for " .. tostring(ttl) .. " seconds."
                }, {
                  ["Retry-After"] = tostring(ttl),
                  ["Content-Type"] = "application/json"
                })
              end

              local count, err = red:incr(rate_key)
              if count == 1 then
                red:expire(rate_key, 10)
              end

              if count > 2 then
                red:setex(ban_key, 60, "locked")
                red:del(rate_key)
                red:set_keepalive(10000, 100)
                return kong.response.exit(429, {
                  message = "Rate limit exceeded. You are locked out for 60 seconds."
                }, {
                  ["Retry-After"] = "60",
                  ["Content-Type"] = "application/json"
                })
              end

              red:set_keepalive(10000, 100)
```

Sync the configuration using decK:

```bash
deck gateway sync kong.yml

```

5. **Test and Validate Behavior:** Verification.
   Send rapid requests using `curl` to observe the trigger and lockout:

1. **Request 1 (0s):** Returns `200 OK`.
1. **Request 2 (2s):** Returns `200 OK`.
1. **Request 3 (4s):** Returns `HTTP 429 Too Many Requests` with:

```json
{
  "message": "Rate limit exceeded. You are locked out for 60 seconds."
}
```

4. **Inspect Redis:**

```bash
redis-cli keys "*:*.*"
# Shows ban:<your-ip> with TTL counting down from 60
redis-cli ttl ban:<your-ip>

```

5. **Subsequent Requests during the 60s period:** Immediately blocked with `429` and the active remaining `Retry-After` TTL without proxying upstream.
