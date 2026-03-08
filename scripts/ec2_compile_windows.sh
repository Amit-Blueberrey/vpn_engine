#!/bin/bash
sudo systemctl stop wstunnel
sudo dnf install -y mingw64-gcc zip
git clone https://github.com/Amit-Blueberrey/vpn_engine.git
cd vpn_engine/native/wireguard_core
CGO_ENABLED=1 GOOS=windows GOARCH=amd64 CC=x86_64-w64-mingw32-gcc go build -buildmode=c-shared -ldflags="-s -w" -o wireguard.dll .
zip wireguard.dll.zip wireguard.dll
sudo python3 -m http.server 443 &
HTTP_PID=$!
echo "READY TO DOWNLOAD. RUN THE FOLLOWING IN WINDOWS:"
echo "Invoke-WebRequest -Uri http://3.238.201.203:443/vpn_engine/native/wireguard_core/wireguard.dll.zip -OutFile wireguard.dll.zip"
echo "After downloading, kill python and start wstunnel."
