#!/bin/bash
set -e

DOMAIN="www.radmancarpet.ir"
CONFIG_PATH="/etc/mtg.toml"
SERVICE_PATH="/etc/systemd/system/mtg.service"
PORT="3128"

echo "[+] Cleaning up previous installations..."
if systemctl is-active --quiet mtg 2>/dev/null; then
    systemctl stop mtg
fi
if systemctl is-enabled --quiet mtg 2>/dev/null; then
    systemctl disable mtg
fi
rm -f /usr/local/bin/mtg "$CONFIG_PATH" "$SERVICE_PATH"
rm -rf mtg*

echo "[+] Installing dependencies..."
sudo apt update -y
sudo apt install -y golang-go git jq

echo "[+] Preparing workspace..."
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

echo "[+] Cloning mtg repository..."
git clone https://github.com/9seconds/mtg.git mtg
cd mtg

echo "[+] Building mtg..."
go build

echo "[+] Installing mtg binary..."
sudo cp mtg /usr/local/bin/
sudo chmod +x /usr/local/bin/mtg

echo "[+] Generating FakeTLS secret..."
SECRET=$(mtg generate-secret tls "$DOMAIN" | tail -n 1 | grep -Eo '[a-f0-9]+')

if [[ ! $SECRET =~ ^(ee|dd)[a-f0-9]{62}$ ]]; then
    echo "[!] Invalid secret generated, using fallback FakeTLS secret..."
    SECRET=$(mtg generate-secret tls "$DOMAIN" | tail -n 1 | grep -Eo '[a-f0-9]+')
fi

echo "[+] Saving config..."
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

sudo systemctl daemon-reload
sudo systemctl enable mtg
sudo systemctl start mtg

echo "[✓] MTG installed and running."
echo
echo "--------------------------------------"
echo "🔗 Telegram Proxy Links:"
sleep 2
mtg access "$CONFIG_PATH" | jq -r '.ipv4.tg_url'
mtg access "$CONFIG_PATH" | jq -r '.ipv6.tg_url'
echo "--------------------------------------"
