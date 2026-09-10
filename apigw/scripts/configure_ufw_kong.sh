#!/usr/bin/env bash
# ==============================================================================
# Configure UFW Firewall for Kong Gateway (Proxy, Admin API & Kong Manager UI)
# ==============================================================================
set -e

# Ensure running with sudo privileges
if [ "$EUID" -ne 0 ]; then
  echo "⚠️  This script requires administrative privileges. Re-running with sudo..."
  exec sudo bash "$0" "$@"
fi

echo "===================================================="
echo "🛡️  Configuring UFW Firewall Rules for Kong Gateway"
echo "===================================================="

# Check if UFW is installed
if ! command -v ufw > /dev/null 2>&1; then
  echo "❌ ERROR: ufw is not installed on this system."
  exit 1
fi

echo -e "\n[1/3] Adding UFW Rules for Kong Gateway..."

# 1. Kong Proxy (HTTP) - Port 8088: Camera VA triggers & API ingress
ufw allow 8088/tcp comment "Kong Gateway HTTP Proxy (VA Ingress)"

# 2. Kong Proxy (HTTPS) - Port 8443: Secure VA triggers & API ingress
ufw allow 8443/tcp comment "Kong Gateway HTTPS Proxy (Secure Ingress)"

# 3. Kong Admin API - Port 8001: Required for Admin API & Kong Manager GUI browser calls
ufw allow 8001/tcp comment "Kong Gateway Admin API"

# 4. Kong Manager UI - Port 8002: Browser Web Dashboard
ufw allow 8002/tcp comment "Kong Gateway Manager Web UI"

echo -e "\n[2/3] Reloading UFW Firewall..."
ufw reload

echo -e "\n[3/3] Updated UFW Firewall Status:"
echo "===================================================="
ufw status verbose | grep -E "8088|8443|8001|8002|Status:" || ufw status verbose

echo "===================================================="
echo "✅ Kong Gateway Firewall Rules Configured Successfully!"
echo "===================================================="
echo "Allowed Ingress Ports:"
echo "  • Port 8088/tcp  -> Kong Proxy HTTP (VA camera triggers)"
echo "  • Port 8443/tcp  -> Kong Proxy HTTPS"
echo "  • Port 8001/tcp  -> Kong Admin API"
echo "  • Port 8002/tcp  -> Kong Manager Web GUI (http://10.65.51.252:8002)"
echo "===================================================="
