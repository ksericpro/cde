#!/usr/bin/env bash
# =============================================================================
#  configure_ufw_monitoring.sh — Open Firewall Ports for Grafana & Prometheus
# =============================================================================
set -euo pipefail

echo "================================================================="
echo "  Configuring Host UFW Firewall Rules for Monitoring Stack       "
echo "================================================================="

if ! command -v ufw >/dev/null 2>&1; then
  echo "[-] ufw command not found. Skipping host firewall configuration."
  exit 0
fi

# Allow incoming monitoring ports
# 3000: Grafana Dashboard UI
# 9090: Prometheus Server API / UI
# 9100: Node Exporter Host Metrics
# 8080: cAdvisor Container Metrics
sudo ufw allow 3000/tcp comment 'CDE Grafana Web UI'
sudo ufw allow 9090/tcp comment 'CDE Prometheus Server'
sudo ufw allow 9100/tcp comment 'CDE Prometheus Node Exporter'
sudo ufw allow 8080/tcp comment 'CDE Google cAdvisor'

echo "[+] Reloading UFW firewall..."
sudo ufw reload

echo "[+] Current UFW Status:"
sudo ufw status verbose | grep -E "(3000|9090|9100|8080)" || true

echo "================================================================="
echo "[+] UFW configuration completed successfully."
echo "================================================================="
