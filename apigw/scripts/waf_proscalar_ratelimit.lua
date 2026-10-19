-- ==============================================================================
-- Kong Gateway WAF Rate Limiter with Penalty Box (Lockout Ban)
-- Target: Proscalar Webhook Ingress (imops-proscalar-n8n-service)
-- ==============================================================================

local redis = require "resty.redis"
local red = redis:new()

-- Fail-fast: 100ms timeout to prevent hanging webhook ingress on network hiccups
red:set_timeout(100)

local ok, err = red:connect("kong-redis", 6379)
if not ok then
  -- Fallback to localhost (port 6380 mapped on host, or 6379) if testing outside container
  ok, err = red:connect("127.0.0.1", 6380)
  if not ok then
    ok, err = red:connect("127.0.0.1", 6379)
    if not ok then
      kong.log.err("[WAF] Redis connection failed, failing open for alarm safety: ", err)
      return -- Fail open: Ensure critical life-safety alarms are not dropped
    end
  end
end

-- Resolve Real Client IP (honoring trusted_ips / X-Forwarded-For)
local client_ip = kong.client.get_forwarded_ip() or kong.client.get_ip() or "unknown"

-- 1. IP Whitelist Bypass (add trusted partner CIDRs or internal server IPs here)
local whitelist = {
  -- ["10.99.0.1"] = true
}
if whitelist[client_ip] then
  red:set_keepalive(10000, 100)
  return
end

local ban_key  = "waf:ban:" .. client_ip
local rate_key = "waf:rate:" .. client_ip

-- Configuration Thresholds Calibrated for Physical Security Webhooks
local burst_window = 10   -- Counter window in seconds
local burst_limit  = 30   -- Requests allowed per window (alarm-safe for multi-zone clusters)
local lockout_ttl  = 60   -- Penalty lockout duration in seconds

-- 2. Check if IP is currently in Lockout Jail
local banned, err_b = red:get(ban_key)
if banned and banned ~= ngx.null then
  local ttl, _ = red:ttl(ban_key)
  if not ttl or ttl < 1 then
    ttl = 1
  end
  red:set_keepalive(10000, 100)
  return kong.response.exit(429, {
    error = "Too Many Requests",
    message = "WAF: Client locked out due to anomalous burst. Try again in " .. tostring(ttl) .. " seconds.",
    retry_after = ttl
  }, {
    ["Retry-After"] = tostring(ttl),
    ["Content-Type"] = "application/json",
    ["X-WAF-Status"] = "Blocked"
  })
end

-- 3. Atomic Rate Counting (Lua script on Redis: INCR and EXPIRE if key is newly created)
local atomic_script = "local c = redis.call('INCR', KEYS[1]) if tonumber(c) == 1 then redis.call('EXPIRE', KEYS[1], ARGV[1]) end return c"
local count, err_eval = red:eval(atomic_script, 1, rate_key, burst_window)
if not count then
  kong.log.err("[WAF] Redis eval failed, failing open: ", err_eval)
  red:set_keepalive(10000, 100)
  return
end

-- 4. Check if Burst Threshold Exceeded -> Trigger Penalty Box
if tonumber(count) > burst_limit then
  red:setex(ban_key, lockout_ttl, "locked")
  red:del(rate_key)
  red:set_keepalive(10000, 100)

  kong.log.warn("[WAF] Lockout triggered for IP ", client_ip, " (burst count: ", count, " > ", burst_limit, "). Banned for ", lockout_ttl, "s.")

  return kong.response.exit(429, {
    error = "Too Many Requests",
    message = "WAF: Burst threshold exceeded (" .. burst_limit .. " req / " .. burst_window .. "s). You are locked out for " .. lockout_ttl .. " seconds.",
    retry_after = lockout_ttl
  }, {
    ["Retry-After"] = tostring(lockout_ttl),
    ["Content-Type"] = "application/json",
    ["X-WAF-Status"] = "Penalized"
  })
end

-- 5. Request allowed: return Redis socket to pool
red:set_keepalive(10000, 100)
