#!/usr/bin/env bash
# ============================================================
# Project X — Setup Script
# Combines RAGFlow (best accuracy) + Kotaemon (best UI)
# Run this once to get started
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║          Project X — RAGFlow + Kotaemon Setup           ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# ── 1. Check prerequisites ──────────────────────────────────
check_cmd() {
  if ! command -v "$1" &>/dev/null; then
    echo "❌  $1 is required but not installed."
    echo "    Install it from: $2"
    exit 1
  fi
  echo "✅  $1 found"
}

echo "Checking prerequisites..."
check_cmd docker    "https://docs.docker.com/get-docker/"
check_cmd docker-compose "https://docs.docker.com/compose/install/" 2>/dev/null || true

# Support both 'docker-compose' and 'docker compose'
if docker compose version &>/dev/null 2>&1; then
  COMPOSE="docker compose"
elif command -v docker-compose &>/dev/null; then
  COMPOSE="docker-compose"
else
  echo "❌  Docker Compose not found. Install Docker Desktop or docker-compose."
  exit 1
fi
echo "✅  Docker Compose found ($COMPOSE)"
echo ""

# ── 2. Create .env from example ─────────────────────────────
if [ ! -f ".env" ]; then
  cp .env.example .env
  echo "📝  Created .env from .env.example"
  echo "    ⚠️  Edit .env to set your API keys and passwords before proceeding."
  echo ""
  read -p "    Press Enter to continue with default dev passwords, or Ctrl+C to edit .env first... "
fi

# ── 3. Pull Docker images ────────────────────────────────────
echo ""
echo "📦  Pulling Docker images (this may take a few minutes)..."
$COMPOSE pull --quiet ragflow es01 mysql minio redis 2>/dev/null || \
  $COMPOSE pull ragflow es01 mysql minio redis

# ── 4. Build Kotaemon image ──────────────────────────────────
echo ""
echo "🔨  Building Kotaemon image..."
$COMPOSE build kotaemon

# ── 5. Start the stack ──────────────────────────────────────
echo ""
echo "🚀  Starting Project X..."
$COMPOSE up -d

# ── 6. Wait for RAGFlow ──────────────────────────────────────
echo ""
echo "⏳  Waiting for RAGFlow to be ready..."
MAX_WAIT=120
WAITED=0
until curl -sf "http://localhost:9380/v1/health" >/dev/null 2>&1 || \
      curl -sf "http://localhost:80"              >/dev/null 2>&1; do
  if [ $WAITED -ge $MAX_WAIT ]; then
    echo "⚠️  RAGFlow is taking a while (still starting up). Check: docker compose logs ragflow"
    break
  fi
  sleep 5
  WAITED=$((WAITED + 5))
  echo "   Still waiting... (${WAITED}s)"
done

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║                    🎉 All Done!                         ║"
echo "╠══════════════════════════════════════════════════════════╣"
echo "║  RAGFlow  (document parsing + retrieval backend)         ║"
echo "║    Web UI : http://localhost:80                          ║"
echo "║    API    : http://localhost:9380                        ║"
echo "║                                                          ║"
echo "║  Kotaemon (beautiful chat UI + citations)               ║"
echo "║    Web UI : http://localhost:7860                        ║"
echo "╠══════════════════════════════════════════════════════════╣"
echo "║  Next steps:                                             ║"
echo "║  1. Open RAGFlow at http://localhost:80                  ║"
echo "║     → Register an account                               ║"
echo "║     → Settings → API Keys → create a key               ║"
echo "║     → Paste it as RAGFLOW_API_KEY in .env               ║"
echo "║  2. Open Kotaemon at http://localhost:7860               ║"
echo "║     → Login (default: admin / admin)                    ║"
echo "║     → Upload documents via the RAGFlow Collection index ║"
echo "║     → Start chatting with citations!                    ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
