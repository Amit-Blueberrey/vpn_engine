#!/usr/bin/env bash
# scripts/build_android.sh
# -------------------------------------------------------------------
# Compiles the WireGuard core into 4 Android .so files (JNI).
# Requires: Go >= 1.21, Android NDK r25c or later.
#           Set ANDROID_NDK_HOME before running.
# Output:   native/prebuilt/android/{arm64-v8a,armeabi-v7a,x86,x86_64}/libwireguard.so
# -------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
SRC_DIR="$ROOT_DIR/native/wireguard_core"
PREBUILT="$ROOT_DIR/native/prebuilt/android"

NDK="${ANDROID_NDK_HOME:?Set ANDROID_NDK_HOME to your NDK path}"
API_LEVEL=21

# ABI → NDK triple → Go GOARCH / GOARM matrix
declare -A ABI_TO_TRIPLE
ABI_TO_TRIPLE["arm64-v8a"]="aarch64-linux-android"
ABI_TO_TRIPLE["armeabi-v7a"]="armv7a-linux-androideabi"
ABI_TO_TRIPLE["x86"]="i686-linux-android"
ABI_TO_TRIPLE["x86_64"]="x86_64-linux-android"

declare -A ABI_TO_GOARCH
ABI_TO_GOARCH["arm64-v8a"]="arm64"
ABI_TO_GOARCH["armeabi-v7a"]="arm"
ABI_TO_GOARCH["x86"]="386"
ABI_TO_GOARCH["x86_64"]="amd64"

declare -A ABI_TO_GOARM
ABI_TO_GOARM["armeabi-v7a"]="7"

HOST_TAG="linux-x86_64"
TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/$HOST_TAG"

for ABI in arm64-v8a armeabi-v7a x86 x86_64; do
  TRIPLE="${ABI_TO_TRIPLE[$ABI]}"
  GOARCH="${ABI_TO_GOARCH[$ABI]}"
  OUT_ABI="$PREBUILT/$ABI"
  mkdir -p "$OUT_ABI"

  CC="$TOOLCHAIN/bin/${TRIPLE}${API_LEVEL}-clang"

  echo "==> Building $ABI libwireguard.so..."
  cd "$SRC_DIR"

  CGO_ENABLED=1 \
    GOOS=android \
    GOARCH="$GOARCH" \
    CGO_CFLAGS="--sysroot=$TOOLCHAIN/sysroot" \
    CGO_LDFLAGS="--sysroot=$TOOLCHAIN/sysroot" \
    CC="$CC" \
    go build \
      -buildmode=c-shared \
      -trimpath \
      -ldflags="-s -w" \
      -o "$OUT_ABI/libwireguard.so" \
      .

  echo "    --> $OUT_ABI/libwireguard.so"
done

echo "==> Android builds complete."
