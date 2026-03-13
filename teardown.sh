#!/usr/bin/env bash
# Tear down the stack and clean up volumes
set -e
cd "$(dirname "${BASH_SOURCE[0]}")"

echo "Stopping Project X..."
docker compose down --volumes --remove-orphans 2>/dev/null || \
  docker-compose down --volumes --remove-orphans

echo "✅  All containers and volumes removed."
