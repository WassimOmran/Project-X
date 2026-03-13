#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
#  Project X — Cloudflare Tunnel
#  Exposes Kotaemon and RAGFlow to the internet for free via
#  an outbound Cloudflare tunnel. Safe, no ports to open.
#  Usage: ./scripts/cloudflare-tunnel.sh
# ─────────────────────────────────────────────────────────────
set -euo pipefail

KOTAEMON_PORT=7860
RAGFLOW_PORT=80
LOG_DIR="$(cd "$(dirname "$0")/.." && pwd)/.tunnel-logs"
mkdir -p "$LOG_DIR"

# ── 1. Install cloudflared if missing ────────────────────────
if ! command -v cloudflared &>/dev/null; then
  echo "cloudflared not found — installing via Homebrew..."
  if ! command -v brew &>/dev/null; then
    echo "ERROR: Homebrew is not installed. Install it from https://brew.sh then re-run."
    exit 1
  fi
  brew install cloudflare/cloudflare/cloudflared
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Project X — Cloudflare Tunnel"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Starting tunnels for Kotaemon (:${KOTAEMON_PORT}) and RAGFlow (:${RAGFLOW_PORT})..."
echo "This may take a few seconds."
echo ""

# ── 2. Kill any existing tunnel processes ────────────────────
pkill -f "cloudflared tunnel" 2>/dev/null || true

# ── 3. Launch Kotaemon tunnel ────────────────────────────────
cloudflared tunnel --url "http://localhost:${KOTAEMON_PORT}" \
  --no-autoupdate \
  2>"$LOG_DIR/kotaemon.log" &
KOTAEMON_PID=$!

# ── 4. Launch RAGFlow tunnel ─────────────────────────────────
cloudflared tunnel --url "http://localhost:${RAGFLOW_PORT}" \
  --no-autoupdate \
  2>"$LOG_DIR/ragflow.log" &
RAGFLOW_PID=$!

# ── 5. Wait for URLs to appear in logs ───────────────────────
echo "Waiting for Cloudflare to assign public URLs..."

get_url() {
  local logfile="$1"
  local tries=0
  while [ $tries -lt 30 ]; do
    local url
    url=$(grep -oE 'https://[a-zA-Z0-9-]+\.trycloudflare\.com' "$logfile" 2>/dev/null | head -1)
    if [ -n "$url" ]; then
      echo "$url"
      return 0
    fi
    sleep 1
    tries=$((tries + 1))
  done
  echo "(URL not found — check $logfile)"
}

KOTAEMON_URL=$(get_url "$LOG_DIR/kotaemon.log")
RAGFLOW_URL=$(get_url "$LOG_DIR/ragflow.log")

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅  Tunnels are LIVE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  🧠  Kotaemon Chat UI  →  ${KOTAEMON_URL}"
echo "  ⚡  RAGFlow Admin UI  →  ${RAGFLOW_URL}"
echo ""
echo "  Share either URL with anyone — it works globally."
echo "  URLs are temporary and change each restart."
echo ""
echo "  Press Ctrl+C to stop both tunnels."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── 6. Keep script alive; clean up on exit ───────────────────
trap 'echo ""; echo "Stopping tunnels..."; kill $KOTAEMON_PID $RAGFLOW_PID 2>/dev/null; exit 0' INT TERM

wait $KOTAEMON_PID $RAGFLOW_PID
