#!/usr/bin/env bash
# =============================================================================
#  verify_monitoring.sh — Verify health and metrics endpoints for monitoring
# =============================================================================
set -euo pipefail

PROMETHEUS_HOST="${1:-http://localhost:9090}"
GRAFANA_HOST="${2:-http://localhost:3000}"
NODE_EXPORTER_HOST="${3:-http://localhost:9100}"
CADVISOR_HOST="${4:-http://localhost:8080}"
KONG_ADMIN_HOST="${5:-http://localhost:8001}"

echo "================================================================="
echo "  Verifying CDE Monitoring Infrastructure Endpoints              "
echo "================================================================="

check_endpoint() {
  local name="$1"
  local url="$2"
  local expected="$3"

  printf "%-25s -> %-35s " "${name}" "${url}"
  local status_code
  status_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "${url}" || echo "DOWN")

  if [[ "${status_code}" == "${expected}"* ]]; then
    echo "[PASS] (HTTP ${status_code})"
  else
    echo "[FAIL] (Expected ${expected}, got ${status_code})"
  fi
}

check_endpoint "Prometheus Ready"       "${PROMETHEUS_HOST}/-/ready" "200"
check_endpoint "Prometheus Targets"     "${PROMETHEUS_HOST}/api/v1/targets" "200"
check_endpoint "Grafana Health"         "${GRAFANA_HOST}/api/health" "200"
check_endpoint "Node Exporter Metrics"  "${NODE_EXPORTER_HOST}/metrics" "200"
check_endpoint "cAdvisor Health"        "${CADVISOR_HOST}/healthz" "200"
check_endpoint "Kong Gateway Metrics"   "${KONG_ADMIN_HOST}/metrics" "200"

echo ""
echo "[*] Active Prometheus Scrape Targets Summary:"
if command -v jq >/dev/null 2>&1; then
  curl -s "${PROMETHEUS_HOST}/api/v1/targets" | jq -r '.data.activeTargets[] | "\(.labels.job) [\(.discoveredLabels.__address__)]: \(.health)"' || true
else
  curl -s "${PROMETHEUS_HOST}/api/v1/targets" | grep -o '"health":"[^"]*"' || true
fi

echo "================================================================="
