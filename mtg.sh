#!/bin/bash
# Exit on error
set -e

# Define your domain and secret here
DOMAIN="www.radmancarpet.ir"
CONFIG_PATH="/etc/mtg.toml"
SERVICE_PATH="/etc/systemd/system/mtg.service"

echo "[+] Installing Go and dependencies..."
sudo apt update
sudo apt install -y golang-go git jq

echo "[+] Cloning mtg repository..."
git clone https://github.com/9seconds/mtg.git
cd mtg

echo "[+] Building mtg..."
go build
sudo cp mtg /usr/local/bin
cd ..
rm -rf mtg

echo "[+] Generating MTProto secret..."
SECRET=$(mtg generate-secret "$DOMAIN" | tail -n 1)

echo "[+] Saving config to $CONFIG_PATH..."
sudo tee "$CONFIG_PATH" > /dev/null <<EOF
secret = "$SECRET"
bind-to = "0.0.0.0:3128"
EOF

echo "[+] Creating systemd service..."
sudo tee "$SERVICE_PATH" > /dev/null <<EOF
[Unit]
Description=mtg - MTProto proxy server
Documentation=https://github.com/9seconds/mtg
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

echo "[✓] MTG installed and running."

# Extract only the tg_url values from the JSON output
echo "Proxy Links:"
mtg access /etc/mtg.toml | jq -r '.ipv4.tg_url'
mtg access /etc/mtg.toml | jq -r '.ipv6.tg_url'
