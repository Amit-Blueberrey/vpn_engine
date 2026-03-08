#!/usr/bin/env bash
# scripts/build_linux.sh
# -------------------------------------------------------------------
# Compiles the WireGuard core into a shared library for Linux x86_64.
# Requires: Go >= 1.21  (CGO_ENABLED=1, gcc/clang)
# Output:   native/prebuilt/linux/libwireguard.so
# -------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
SRC_DIR="$ROOT_DIR/native/wireguard_core"
OUT_DIR="$ROOT_DIR/native/prebuilt/linux"

mkdir -p "$OUT_DIR"

echo "==> Building libwireguard.so (Linux x86_64)..."
cd "$SRC_DIR"

CGO_ENABLED=1 \
  GOOS=linux \
  GOARCH=amd64 \
  go build \
    -buildmode=c-shared \
    -trimpath \
    -ldflags="-s -w" \
    -o "$OUT_DIR/libwireguard.so" \
    .

# Copy the generated header
cp "$SRC_DIR/wireguard.h" "$OUT_DIR/wireguard.h"

echo "==> Done: $OUT_DIR/libwireguard.so"
