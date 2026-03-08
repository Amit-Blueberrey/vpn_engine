#!/usr/bin/env bash
# scripts/build_windows.sh
# -------------------------------------------------------------------
# Compiles the WireGuard core into wireguard.dll for Windows x64.
# Must run on Linux (cross-compile) or on Windows via MSYS2/Cygwin.
# Requires: Go >= 1.21 with mingw64 CGO toolchain.
#           On Linux:  apt-get install gcc-mingw-w64-x86-64
# Output:   native/prebuilt/windows/wireguard.dll
# Note:     wintun.dll is downloaded from https://www.wintun.net/
#           and must be placed alongside wireguard.dll at runtime.
# -------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
SRC_DIR="$ROOT_DIR/native/wireguard_core"
OUT_DIR="$ROOT_DIR/native/prebuilt/windows"

mkdir -p "$OUT_DIR"

echo "==> Building wireguard.dll (Windows x64)..."
cd "$SRC_DIR"

CGO_ENABLED=1 \
  GOOS=windows \
  GOARCH=amd64 \
  CC=x86_64-w64-mingw32-gcc \
  go build \
    -buildmode=c-shared \
    -trimpath \
    -ldflags="-s -w" \
    -o "$OUT_DIR/wireguard.dll" \
    .

cp "$SRC_DIR/wireguard.h" "$OUT_DIR/wireguard.h"

# Download Wintun (required for Windows TUN adapter)
WINTUN_ZIP="$OUT_DIR/wintun.zip"
WINTUN_URL="https://www.wintun.net/builds/wintun-0.14.1.zip"
if [ ! -f "$OUT_DIR/wintun.dll" ]; then
  echo "==> Downloading wintun.dll..."
  curl -fsSL "$WINTUN_URL" -o "$WINTUN_ZIP"
  unzip -j "$WINTUN_ZIP" "wintun/bin/amd64/wintun.dll" -d "$OUT_DIR"
  rm "$WINTUN_ZIP"
fi

echo "==> Done: $OUT_DIR/wireguard.dll + wintun.dll"
