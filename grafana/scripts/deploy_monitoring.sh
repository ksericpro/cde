#!/usr/bin/env bash
# =============================================================================
#  deploy_monitoring.sh — Initialize and launch Grafana & Prometheus stack
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GRAFANA_DIR="$(dirname "$SCRIPT_DIR")"

echo "================================================================="
echo "  Deploying CDE Monitoring Stack (Grafana + Prometheus)          "
echo "  Directory: ${GRAFANA_DIR}                                      "
echo "================================================================="

cd "${GRAFANA_DIR}"

# 1. Ensure .env exists
if [ ! -f ".env" ]; then
  echo "[*] .env file not found. Copying from .env.example..."
  cp .env.example .env
fi

# 2. Check / Create external network 'cde-network'
if ! docker network inspect cde-network >/dev/null 2>&1; then
  echo "[+] Creating external Docker network 'cde-network'..."
  docker network create cde-network
else
  echo "[+] Docker network 'cde-network' already exists."
fi

# 3. Pull latest images and launch containers
echo "[+] Starting containers via docker compose..."
docker compose up -d

echo ""
echo "[+] Monitoring stack deployed successfully!"
echo "    - Grafana Web UI:       http://localhost:3000 (admin / cdepassword123)"
echo "    - Prometheus Targets:   http://localhost:9090/targets"
echo "    - Node Exporter:        http://localhost:9100/metrics"
echo "    - cAdvisor:             http://localhost:8080/containers"
echo "================================================================="
