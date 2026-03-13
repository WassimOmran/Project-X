#!/usr/bin/env bash
# ============================================================
# Project X — Oracle Cloud Server Setup Script
# Run this ONCE on your Oracle Ubuntu 22.04 instance
#
# Usage:
#   chmod +x oracle-setup.sh
#   ./oracle-setup.sh YOUR_OPENAI_API_KEY
#
# What this does:
#   1. Updates system packages
#   2. Installs Docker + Docker Compose
#   3. Opens required firewall ports
#   4. Clones Project X from GitHub
#   5. Configures .env with your API key
#   6. Launches the full stack
# ============================================================
set -e

OPENAI_KEY="${1:-}"
REPO_URL="https://github.com/WassimOmran/Project-X.git"
INSTALL_DIR="$HOME/project-x"

# Colors
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; NC='\033[0m'
log()  { echo -e "${B}[Project X]${NC} $1"; }
ok()   { echo -e "${G}✓${NC} $1"; }
warn() { echo -e "${Y}⚠${NC}  $1"; }
err()  { echo -e "${R}✗${NC} $1"; exit 1; }

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║     Project X — Oracle Cloud Auto Setup                 ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# ── 1. System update ─────────────────────────────────────────
log "Updating system packages..."
sudo apt-get update -qq
sudo apt-get upgrade -y -qq
sudo apt-get install -y -qq curl git wget unzip ca-certificates gnupg lsb-release
ok "System updated"

# ── 2. Install Docker ────────────────────────────────────────
if command -v docker &>/dev/null; then
  ok "Docker already installed ($(docker --version))"
else
  log "Installing Docker..."
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt-get update -qq
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
  sudo usermod -aG docker "$USER"
  sudo systemctl enable docker
  sudo systemctl start docker
  ok "Docker installed"
fi

# ── 3. Set memory limits (Oracle ARM has 24GB, be generous) ──
log "Configuring Docker memory settings..."
sudo mkdir -p /etc/docker
cat <<EOF | sudo tee /etc/docker/daemon.json > /dev/null
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" },
  "default-ulimits": { "nofile": { "Name": "nofile", "Hard": 65536, "Soft": 65536 } }
}
EOF
sudo systemctl restart docker
ok "Docker configured"

# ── 4. Open Oracle firewall (iptables) ───────────────────────
log "Opening firewall ports (80, 443, 7860, 9380)..."
# Oracle Linux uses iptables by default — open required ports
for PORT in 80 443 7860 9380; do
  sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport $PORT -j ACCEPT 2>/dev/null || true
done
# Persist rules
if command -v netfilter-persistent &>/dev/null; then
  sudo netfilter-persistent save
else
  sudo apt-get install -y -qq iptables-persistent netfilter-persistent
  sudo netfilter-persistent save
fi
ok "Firewall ports opened"

# ── 5. Clone Project X ───────────────────────────────────────
if [ -d "$INSTALL_DIR" ]; then
  warn "Directory $INSTALL_DIR already exists, pulling latest..."
  cd "$INSTALL_DIR" && git pull && git submodule update --init --recursive
else
  log "Cloning Project X..."
  git clone --recurse-submodules "$REPO_URL" "$INSTALL_DIR"
fi
cd "$INSTALL_DIR"
ok "Repository ready at $INSTALL_DIR"

# ── 6. Configure .env ────────────────────────────────────────
if [ ! -f ".env" ]; then
  cp .env.example .env
fi

# Generate secure random passwords
gen_pass() { openssl rand -hex 16; }

# Update passwords in .env (replace defaults)
sed -i "s/projectx_elastic_changeme/$(gen_pass)/g" .env
sed -i "s/projectx_mysql_changeme/$(gen_pass)/g"   .env
sed -i "s/projectx_root_changeme/$(gen_pass)/g"    .env
sed -i "s/projectx_minio_changeme/$(gen_pass)/g"   .env
sed -i "s/projectx_redis_changeme/$(gen_pass)/g"   .env

# Add OpenAI key if provided
if [ -n "$OPENAI_KEY" ]; then
  if grep -q "^OPENAI_API_KEY=" .env; then
    sed -i "s|^OPENAI_API_KEY=.*|OPENAI_API_KEY=${OPENAI_KEY}|" .env
  else
    echo "OPENAI_API_KEY=${OPENAI_KEY}" >> .env
  fi
  ok "OpenAI API key configured"
else
  warn "No OpenAI key provided. Add it later: echo 'OPENAI_API_KEY=sk-...' >> .env"
fi

ok ".env configured with secure passwords"

# ── 7. Set vm.max_map_count for Elasticsearch ────────────────
log "Setting vm.max_map_count for Elasticsearch..."
sudo sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf > /dev/null
ok "Elasticsearch memory configured"

# ── 8. Launch the stack ──────────────────────────────────────
log "Launching Project X (pulling images, this takes ~5 minutes first time)..."
docker compose pull
docker compose up -d
ok "Stack launched!"

# ── 9. Wait for services ─────────────────────────────────────
log "Waiting for services to be ready..."
sleep 15

SERVER_IP=$(curl -s --max-time 5 ifconfig.me || hostname -I | awk '{print $1}')

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║              🎉 Project X is Live!                      ║"
echo "╠══════════════════════════════════════════════════════════╣"
printf "║  Kotaemon (Chat UI)  →  http://%-26s║\n" "${SERVER_IP}:7860  "
printf "║  RAGFlow  (Backend)  →  http://%-26s║\n" "${SERVER_IP}:80    "
printf "║  RAGFlow  (API)      →  http://%-26s║\n" "${SERVER_IP}:9380  "
echo "╠══════════════════════════════════════════════════════════╣"
echo "║  Next steps:                                             ║"
echo "║  1. Open RAGFlow → register → Settings → API Keys       ║"
echo "║  2. Add key to .env: RAGFLOW_API_KEY=ragflow-xxxxx      ║"
echo "║  3. Run: docker compose restart kotaemon                ║"
echo "║  4. Open Kotaemon → login: admin / admin                ║"
echo "║  5. Upload docs → RAGFlow Collection → chat!            ║"
echo "╠══════════════════════════════════════════════════════════╣"
echo "║  NOTE: Also open ports in Oracle Cloud Console:         ║"
echo "║  VCN → Security List → Add Ingress Rules for:           ║"
echo "║  TCP 80, 443, 7860, 9380  (source: 0.0.0.0/0)          ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "  Your server IP: $SERVER_IP"
echo ""
echo "  Useful commands:"
echo "    docker compose logs -f kotaemon   # view kotaemon logs"
echo "    docker compose logs -f ragflow    # view ragflow logs"
echo "    docker compose down               # stop everything"
echo "    docker compose up -d              # start again"
echo ""
