#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
#  Project X — Deploy Cloudflare Worker (one-time setup)
#  Run this once to deploy the auth-gate Worker to Cloudflare.
#  After deploying, use ./scripts/cloudflare-tunnel.sh as normal.
# ─────────────────────────────────────────────────────────────
set -euo pipefail

WORKER_DIR="$(cd "$(dirname "$0")/.." && pwd)/cloudflare-worker"

# ── 1. Check wrangler ─────────────────────────────────────────
if ! command -v wrangler &>/dev/null; then
  echo "ERROR: wrangler is not installed."
  echo "Install it with: npm install -g wrangler"
  exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Project X — Worker Setup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── 2. Login to Cloudflare ────────────────────────────────────
echo "Step 1/3 — Log in to Cloudflare (browser will open)..."
wrangler login

# ── 3. Set ACCESS_KEY secret ──────────────────────────────────
echo ""
echo "Step 2/3 — Set your access key (the password users must enter)."
echo "Type your secret key then press Enter:"
wrangler secret put ACCESS_KEY --config "$WORKER_DIR/wrangler.toml"

# ── 4. Deploy Worker ──────────────────────────────────────────
echo ""
echo "Step 3/3 — Deploying Worker to Cloudflare..."
cd "$WORKER_DIR"
wrangler deploy

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅  Worker deployed!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Your permanent protected URL:"
echo "  🔐  https://project-x-auth.<your-subdomain>.workers.dev"
echo ""
echo "  Now run ./scripts/cloudflare-tunnel.sh to start the app."
echo "  The tunnel script will automatically link the Worker to the live tunnel."
echo ""
echo "  To update your access key anytime:"
echo "  wrangler secret put ACCESS_KEY --config cloudflare-worker/wrangler.toml"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
