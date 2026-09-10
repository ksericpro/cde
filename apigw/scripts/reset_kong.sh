#!/usr/bin/env bash
# ==============================================================================
# Reset Kong Gateway: Remove all Plugins, Routes, Services, and Consumers
# ==============================================================================
set -e

ADMIN_URL="${KONG_ADMIN_URL:-http://localhost:8001}"

echo "===================================================="
echo "⚠️  Kong Gateway Reset / Purge Utility"
echo "   Target Admin API: $ADMIN_URL"
echo "===================================================="

# Check if Admin API is accessible
if ! curl -s -f "$ADMIN_URL/status" > /dev/null 2>&1; then
  echo "❌ ERROR: Cannot connect to Kong Admin API at $ADMIN_URL!"
  exit 1
fi

# Confirmation prompt unless -y or --yes is passed
if [ "$1" != "-y" ] && [ "$1" != "--yes" ]; then
  read -p "⚠️  Are you sure you want to DELETE ALL Kong plugins, routes, services, and consumers? (y/N): " CONFIRM
  if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Aborted. No changes made."
    exit 0
  fi
fi

echo -e "\n[1/4] Deleting all Plugins..."
PLUGINS=$(curl -s "$ADMIN_URL/plugins" | grep -o '"id":"[^"]*' | cut -d'"' -f4 || true)
if [ -n "$PLUGINS" ]; then
  for id in $PLUGINS; do
    echo "  • Deleting plugin: $id"
    curl -s -X DELETE "$ADMIN_URL/plugins/$id" > /dev/null
  done
  echo "  ✅ All plugins deleted."
else
  echo "  • No plugins found."
fi

echo -e "\n[2/4] Deleting all Routes..."
ROUTES=$(curl -s "$ADMIN_URL/routes" | grep -o '"id":"[^"]*' | cut -d'"' -f4 || true)
if [ -n "$ROUTES" ]; then
  for id in $ROUTES; do
    echo "  • Deleting route: $id"
    curl -s -X DELETE "$ADMIN_URL/routes/$id" > /dev/null
  done
  echo "  ✅ All routes deleted."
else
  echo "  • No routes found."
fi

echo -e "\n[3/4] Deleting all Services..."
SERVICES=$(curl -s "$ADMIN_URL/services" | grep -o '"id":"[^"]*' | cut -d'"' -f4 || true)
if [ -n "$SERVICES" ]; then
  for id in $SERVICES; do
    echo "  • Deleting service: $id"
    curl -s -X DELETE "$ADMIN_URL/services/$id" > /dev/null
  done
  echo "  ✅ All services deleted."
else
  echo "  • No services found."
fi

echo -e "\n[4/4] Deleting all Consumers..."
CONSUMERS=$(curl -s "$ADMIN_URL/consumers" | grep -o '"id":"[^"]*' | cut -d'"' -f4 || true)
if [ -n "$CONSUMERS" ]; then
  for id in $CONSUMERS; do
    echo "  • Deleting consumer: $id"
    curl -s -X DELETE "$ADMIN_URL/consumers/$id" > /dev/null
  done
  echo "  ✅ All consumers deleted."
else
  echo "  • No consumers found."
fi

echo -e "\n===================================================="
echo "✨ Kong Gateway Reset Complete! All configurations purged."
echo "===================================================="
