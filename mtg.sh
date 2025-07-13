#!/bin/bash
# Exit on error
set -e

# Define your domain and secret here
DOMAIN="www.radmancarpet.ir"
CONFIG_PATH="/etc/mtg.toml"
SERVICE_PATH="/etc/systemd/system/mtg.service"

echo "[+] Cleaning up previous installations..."
# Stop and disable service if it exists
if systemctl is-active --quiet mtg 2>/dev/null; then
    echo "[!] Stopping existing mtg service..."
    sudo systemctl stop mtg
fi
if systemctl is-enabled --quiet mtg 2>/dev/null; then
    echo "[!] Disabling existing mtg service..."
    sudo systemctl disable mtg
fi

# Remove old files if they exist
if [ -f /usr/local/bin/mtg ]; then
    echo "[!] Removing existing mtg binary..."
    sudo rm -f /usr/local/bin/mtg
fi
if [ -f "$CONFIG_PATH" ]; then
    echo "[!] Removing existing config file..."
    sudo rm -f "$CONFIG_PATH"
fi
if [ -f "$SERVICE_PATH" ]; then
    echo "[!] Removing existing service file..."
    sudo rm -f "$SERVICE_PATH"
fi

# Clean up any existing mtg directories in current path
if [ -d "mtg" ]; then
    echo "[!] Removing existing mtg directory..."
    rm -rf mtg
fi
# Clean up any timestamped mtg directories
for dir in mtg-*; do
    if [ -d "$dir" ]; then
        echo "[!] Removing existing directory: $dir"
        rm -rf "$dir"
    fi
done 2>/dev/null || true

echo "[+] Installing Go and dependencies..."
sudo apt update
sudo apt install -y golang-go git jq

echo "[+] Preparing workspace..."
# Create a unique temporary directory
TEMP_DIR=$(mktemp -d)
echo "[+] Working in temporary directory: $TEMP_DIR"
cd "$TEMP_DIR"

echo "[+] Downloading mtg repository..."
# Use a unique directory name to avoid conflicts
REPO_DIR="mtg-$(date +%s)"
git clone https://github.com/9seconds/mtg.git "$REPO_DIR"
cd "$REPO_DIR"

echo "[+] Building mtg..."
go build

echo "[+] Installing mtg binary..."
sudo cp mtg /usr/local/bin/
sudo chmod +x /usr/local/bin/mtg

echo "[+] Cleaning up build directory..."
cd /
rm -rf "$TEMP_DIR"

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
