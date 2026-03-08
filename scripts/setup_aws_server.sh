#!/bin/bash

# setup_aws_server.sh
# 
# Phase 6: Automatic AWS WireGuard + WebSocket Fallback Installer
# Optimized for Amazon Linux 2023 / Ubuntu 22.04 (Free Tier t3.micro)

set -e

# --- Configuration ---
SERVER_IP=$(curl -s http://checkip.amazonaws.com)
WG_PORT=51820
WS_PORT=443
WS_TOKEN="secret-vantage-relay-2026" # Change this for production!
IFACE="eth0"

echo "--------------------------------------------------"
echo "🚀 VPN Engine Server Setup (AWS Free Tier)"
echo "Public IP: $SERVER_IP"
echo "--------------------------------------------------"

# 1. Install Dependencies
echo "📦 Installing WireGuard and Go..."
if [ -f /etc/amazon-linux-release ]; then
    sudo dnf update -y
    sudo dnf install -y wireguard-tools golang git
elif [ -f /etc/lsb-release ]; then
    sudo apt-get update
    sudo apt-get install -y wireguard golang-go git
fi

# 2. Enable IP Forwarding
echo "🌐 Enabling IP Forwarding..."
sudo sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf

# 3. Generate Keys
echo "🔑 Generating WireGuard Keys..."
mkdir -p ./wg_keys
wg genkey | tee ./wg_keys/server_private | wg pubkey > ./wg_keys/server_public
wg genkey | tee ./wg_keys/client_private | wg pubkey > ./wg_keys/client_public

SERVER_PRIV=$(cat ./wg_keys/server_private)
SERVER_PUB=$(cat ./wg_keys/server_public)
CLIENT_PRIV=$(cat ./wg_keys/client_private)
CLIENT_PUB=$(cat ./wg_keys/client_public)

# 4. Create wg0.conf
echo "📝 Configuring WireGuard (wg0.conf)..."
sudo mkdir -p /etc/wireguard
cat <<EOF | sudo tee /etc/wireguard/wg0.conf
[Interface]
PrivateKey = $SERVER_PRIV
Address = 10.0.0.1/24
ListenPort = $WG_PORT

# IP Masquerading (NAT) for Internet Access
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o $IFACE -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o $IFACE -j MASQUERADE

[Peer]
PublicKey = $CLIENT_PUB
AllowedIPs = 10.0.0.2/32
EOF

sudo chmod 600 /etc/wireguard/wg0.conf
sudo wg-quick up wg0 || true
sudo systemctl enable wg-quick@wg0

# 5. Install wstunnel (WebSocket Relay for Fallback)
echo "🔌 Setting up WebSocket Fallback (WSTunnel)..."
# We download pre-built binary for x86_64
WSTUNNEL_VER="v9.2.4"
curl -L "https://github.com/erebe/wstunnel/releases/download/${WSTUNNEL_VER}/wstunnel_${WSTUNNEL_VER}_linux_amd64.tar.gz" -o wstunnel.tar.gz
tar -xzf wstunnel.tar.gz
sudo mv wstunnel /usr/local/bin/

# 6. Create Systemd Service for WSTunnel
# This listens on 443 (TCP) and forwards to 51820 (UDP)
cat <<EOF | sudo tee /etc/systemd/system/wstunnel.service
[Unit]
Description=WSTunnel WebSocket Relay for VPN Fallback
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/wstunnel server --restrict-to 127.0.0.1:51820 wss://0.0.0.0:443
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable wstunnel
sudo systemctl start wstunnel

# 7. Generate Client Config
echo "--------------------------------------------------"
echo "✅ SETUP COMPLETE!"
echo "--------------------------------------------------"
echo "📱 CLIENT CONFIGURATION (Standard UDP):"
cat <<EOF
[Interface]
PrivateKey = $CLIENT_PRIV
Address = 10.0.0.2/32
DNS = 1.1.1.1

[Peer]
PublicKey = $SERVER_PUB
Endpoint = $SERVER_IP:$WG_PORT
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 20
EOF

echo ""
echo "🔄 CLIENT CONFIGURATION (WebSocket Fallback):"
echo "Relay URL: wss://$SERVER_IP:$WS_PORT"
echo "Relay Token: $WS_TOKEN"
echo "--------------------------------------------------"
echo "🔥 IMPORTANT: In AWS Console, open Port UDP $WG_PORT and TCP $WS_PORT in Security Groups!"
echo "--------------------------------------------------"
