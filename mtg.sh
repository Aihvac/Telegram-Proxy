#!/usr/bin/env bash
# install_run_mtg_https.sh
# MTProxy setup with real TLS via Let's Encrypt + nginx reverse proxy
# Usage:
#   sudo bash install_run_mtg_https.sh                # uses default domain
#   sudo bash install_run_mtg_https.sh example.com   # uses custom domain

set -euo pipefail

DEFAULT_DOMAIN="www.parandsahandcarpet.ir"
DOMAIN="${1:-$DEFAULT_DOMAIN}"
MTG_USER="mtgproxy"
SERVICE_NAME="mtg-proxy"
MTG_PORT=8443    # Internal MTProxy port
NGINX_PORT=443   # Public HTTPS port

echo "Domain: $DOMAIN"

# Check root
if [ "$(id -u)" -ne 0 ]; then
    echo "Run this script as root."
    exit 1
fi

# Install required packages
apt update
apt install -y mtg nginx certbot python3-certbot-nginx ufw

# Allow firewall
ufw allow 22
ufw allow 443
ufw enable || true

# Create system user for MTProxy
if ! id -u "$MTG_USER" >/dev/null 2>&1; then
    useradd --system --no-create-home --shell /usr/sbin/nologin "$MTG_USER"
fi

# Generate secret
SECRET="$(mtg generate-secret 2>/dev/null || head -c 16 /dev/urandom | xxd -p -c 32)"
echo "Generated secret: $SECRET"

# MTProxy systemd service
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}.service"
cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=MTProxy Telegram Proxy
After=network.target

[Service]
User=$MTG_USER
Group=$MTG_USER
Type=simple
ExecStart=$(command -v mtg) run --port $MTG_PORT --secret $SECRET
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now "$SERVICE_NAME"

# Obtain TLS certificate with certbot (nginx plugin)
certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m admin@$DOMAIN || true

# Configure nginx reverse proxy for MTProxy
NGINX_CONF="/etc/nginx/sites-available/mtproxy"
cat > "$NGINX_CONF" <<EOF
server {
    listen 443 ssl http2;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:$MTG_PORT;
        proxy_buffering off;
        proxy_redirect off;
    }
}
EOF

ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/mtproxy
nginx -t && systemctl reload nginx

# Display proxy link
echo
echo "=== Telegram Proxy Info ==="
echo "Server: $DOMAIN"
echo "Port: 443 (TLS via nginx)"
echo "Secret: $SECRET"
echo
echo "Telegram proxy link:"
echo "tg://proxy?server=${DOMAIN}&port=443&secret=${SECRET}"
echo "==========================="
