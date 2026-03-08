#!/usr/bin/env bash
# scripts/build_apple.sh
# -------------------------------------------------------------------
# Compiles WireGuard core into a universal XCFramework for iOS + macOS.
# Must run on macOS with Xcode Command Line Tools installed.
# Requires: Go >= 1.21, gomobile (for XCFramework packaging).
#           Install: go install golang.org/x/mobile/cmd/gomobile@latest
#                    gomobile init
# Output:   native/prebuilt/apple/WireGuard.xcframework
# -------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
SRC_DIR="$ROOT_DIR/native/wireguard_core"
OUT_DIR="$ROOT_DIR/native/prebuilt/apple"
TEMP_DIR=$(mktemp -d)

mkdir -p "$OUT_DIR"

cd "$SRC_DIR"

build_slice() {
  local GOOS="$1"
  local GOARCH="$2"
  local SUFFIX="$3"
  local OUT_LIB="$TEMP_DIR/libwireguard_${SUFFIX}.a"

  echo "==> Building static slice: $GOOS/$GOARCH..."
  CGO_ENABLED=1 \
    GOOS="$GOOS" \
    GOARCH="$GOARCH" \
    go build \
      -buildmode=c-archive \
      -trimpath \
      -ldflags="-s -w" \
      -o "$OUT_LIB" \
      .
  echo "    --> $OUT_LIB"
}

# ── iOS device (arm64) ────────────────────────────────────────────────────────
SDK_IOS=$(xcrun --sdk iphoneos --show-sdk-path)
CGO_CFLAGS="-isysroot $SDK_IOS -arch arm64 -miphoneos-version-min=14.0" \
  CGO_LDFLAGS="-isysroot $SDK_IOS -arch arm64" \
  CC="$(xcrun -sdk iphoneos -find clang)" \
  build_slice ios arm64 "ios_arm64"

# ── iOS Simulator (arm64 on Apple Silicon, x86_64 on Intel Macs) ──────────────
SDK_SIM=$(xcrun --sdk iphonesimulator --show-sdk-path)
CGO_CFLAGS="-isysroot $SDK_SIM -arch arm64 -miphonesimulator-version-min=14.0" \
  CGO_LDFLAGS="-isysroot $SDK_SIM -arch arm64" \
  CC="$(xcrun -sdk iphonesimulator -find clang)" \
  build_slice ios arm64 "iossim_arm64"

# ── macOS arm64 (Apple Silicon) ───────────────────────────────────────────────
build_slice darwin arm64 "macos_arm64"

# ── macOS x86_64 (Intel) ─────────────────────────────────────────────────────
build_slice darwin amd64 "macos_x86_64"

# ── Lipo macOS slices into fat binary ─────────────────────────────────────────
MACOS_DIR="$TEMP_DIR/macos"
mkdir -p "$MACOS_DIR"
lipo -create \
  "$TEMP_DIR/libwireguard_macos_arm64.a" \
  "$TEMP_DIR/libwireguard_macos_x86_64.a" \
  -output "$MACOS_DIR/libwireguard.a"
cp "$SRC_DIR/wireguard.h" "$MACOS_DIR/wireguard.h"

# ── Create XCFramework ────────────────────────────────────────────────────────
IOS_DIR="$TEMP_DIR/ios_arm64_dir"
IOSSIM_DIR="$TEMP_DIR/iossim_dir"
mkdir -p "$IOS_DIR" "$IOSSIM_DIR"
cp "$TEMP_DIR/libwireguard_ios_arm64.a"  "$IOS_DIR/libwireguard.a"
cp "$TEMP_DIR/libwireguard_iossim_arm64.a" "$IOSSIM_DIR/libwireguard.a"
cp "$SRC_DIR/wireguard.h" "$IOS_DIR/wireguard.h"
cp "$SRC_DIR/wireguard.h" "$IOSSIM_DIR/wireguard.h"

xcodebuild -create-xcframework \
  -library "$IOS_DIR/libwireguard.a" \
    -headers "$SRC_DIR" \
  -library "$IOSSIM_DIR/libwireguard.a" \
    -headers "$SRC_DIR" \
  -library "$MACOS_DIR/libwireguard.a" \
    -headers "$SRC_DIR" \
  -output "$OUT_DIR/WireGuard.xcframework"

rm -rf "$TEMP_DIR"

echo "==> Done: $OUT_DIR/WireGuard.xcframework"
