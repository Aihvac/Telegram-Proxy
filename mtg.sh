#!/usr/bin/env bash
# install_run_mtg.sh
# Script to install mtg, generate secret, and run MTProxy as a systemd service
# Default domain: www.parandsahandcarpet.ir
# Usage:
#   sudo bash install_run_mtg.sh                # uses default domain
#   sudo bash install_run_mtg.sh example.com   # uses custom domain

set -euo pipefail

# ---------- Config ----------
DEFAULT_DOMAIN="www.parandsahandcarpet.ir"
DOMAIN="${1:-$DEFAULT_DOMAIN}"
PORT=443
SERVICE_NAME="mtg-proxy"
MTG_USER="mtgproxy"
# ----------------------------

echo "Domain: $DOMAIN"
echo "Port: $PORT"

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root."
  exit 1
fi

# Install mtg if not present (Debian/Ubuntu)
if ! command -v mtg >/dev/null 2>&1; then
  echo "mtg not found. Installing..."
  apt update
  apt install -y mtg || { echo "mtg installation failed"; exit 1; }
else
  echo "mtg is already installed: $(command -v mtg)"
fi

# Create system user for service if not exists
if ! id -u "$MTG_USER" >/dev/null 2>&1; then
  useradd --system --no-create-home --shell /usr/sbin/nologin "$MTG_USER"
fi

# Generate secret
SECRET="$(mtg generate-secret 2>/dev/null || head -c 16 /dev/urandom | xxd -p -c 32)"
echo "Generated secret: $SECRET"

# Find mtg path
MTG_BIN="$(command -v mtg || echo /usr/bin/mtg)"

# Create systemd service file
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}.service"
cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=MTProxy Telegram Proxy
After=network.target

[Service]
User=$MTG_USER
Group=$MTG_USER
Type=simple
ExecStart=$MTG_BIN run --port $PORT --tls $DOMAIN --secret $SECRET
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd, enable & start service
systemctl daemon-reload
systemctl enable --now "${SERVICE_NAME}.service"

sleep 1

# Check service status
if systemctl is-active --quiet "${SERVICE_NAME}.service"; then
  echo "Service $SERVICE_NAME started successfully."
else
  echo "Service failed to start. Check logs:"
  journalctl -u "${SERVICE_NAME}.service" --no-pager -n 100
  exit 1
fi

# Print proxy link
echo
echo "=== Telegram Proxy Info ==="
echo "Server: $DOMAIN"
echo "Port:   $PORT"
echo "Secret: $SECRET"
echo
echo "Telegram proxy link:"
echo "tg://proxy?server=${DOMAIN}&port=${PORT}&secret=${SECRET}"
echo "==========================="
