#!/bin/bash
set -e

DOMAIN="www.radmancarpet.ir"
CONFIG_PATH="/etc/mtg.toml"
SERVICE_PATH="/etc/systemd/system/mtg.service"
PORT="3128"

echo "[+] Cleaning up previous installations..."
sudo systemctl stop mtg 2>/dev/null || true
sudo systemctl disable mtg 2>/dev/null || true
sudo rm -f /usr/local/bin/mtg "$CONFIG_PATH" "$SERVICE_PATH" 2>/dev/null || true
sudo rm -f /etc/apt/sources.list.d/ookla_speedtest-cli.list 2>/dev/null || true

echo "[+] Installing Go and dependencies..."
sudo apt update -y
sudo apt install -y golang-go git jq

TEMP_DIR=$(mktemp -d)
echo "[+] Working in temporary directory: $TEMP_DIR"
cd "$TEMP_DIR"

echo "[+] Cloning mtg repository..."
git clone https://github.com/9seconds/mtg.git
cd mtg

echo "[+] Building mtg..."
go build -o mtg

echo "[+] Installing mtg binary..."
sudo mv mtg /usr/local/bin/
sudo chmod +x /usr/local/bin/mtg

echo "[+] Generating MTProto secret..."
SECRET=$(mtg generate-secret "$DOMAIN" | grep -oE '[0-9a-fA-F]{64}$' || true)

if [ -z "$SECRET" ]; then
    echo "[⚠️] Failed to generate secret automatically, generating random one..."
    SECRET=$(openssl rand -hex 32)
fi

echo "[+] Creating config file..."
sudo tee "$CONFIG_PATH" > /dev/null <<EOF
secret = "$SECRET"
bind-to = "0.0.0.0:$PORT"
EOF

echo "[+] Creating systemd service..."
sudo tee "$SERVICE_PATH" > /dev/null <<EOF
[Unit]
Description=mtg - MTProto proxy server
After=network.target

[Service]
ExecStart=/usr/local/bin/mtg run $CONFIG_PATH
Restart=always
RestartSec=3
DynamicUser=true
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF

echo "[+] Enabling and starting mtg service..."
sudo systemctl daemon-reload
sudo systemctl enable mtg
sudo systemctl start mtg

if ! systemctl is-active --quiet mtg; then
    echo "[⚠️] mtg service failed to start. Check logs using: sudo journalctl -u mtg -e"
else
    echo "[✓] MTG installed and running successfully."
fi

echo ""
echo "📡 Proxy Links:"
if mtg access "$CONFIG_PATH" &>/dev/null; then
    mtg access "$CONFIG_PATH" | jq -r '.ipv4.tg_url'
    mtg access "$CONFIG_PATH" | jq -r '.ipv6.tg_url'
else
    echo "⚠️ Could not retrieve links automatically. Try manually:"
    echo "mtg access $CONFIG_PATH"
fi

echo ""
echo "🌐 Domain: $DOMAIN"
echo "🔑 Secret: $SECRET"
echo "🚪 Port: $PORT"
