# WireGuard VPN Engine — Proprietary Native Flutter Implementation

**Zero third-party VPN wrappers. Zero shell hacks. Pure Dart FFI → native C.**

---

## Platform Support Matrix

| Platform | Native Backend | TUN Mechanism |
|---|---|---|
| **Windows** | `wireguard.dll` + `wintun.dll` | Wintun kernel adapter |
| **Linux** (Ubuntu/Kali/Debian/Arch) | `libwireguard.so` | `/dev/net/tun` via kernel module |
| **Android** | `libwireguard.so` (JNI) | `VpnService.Builder.establish()` fd |
| **iOS** | `WireGuard.xcframework` (static) | `NetworkExtension` PacketTunnelProvider |
| **macOS** | `WireGuard.xcframework` (static) | `NetworkExtension` NEPacketTunnelProvider |

---

## Repository Structure

```
native/
  wireguard_core/
    wireguard.h       ← C-API header (the ABI contract)
    main.go           ← CGO Go implementation
    go.mod            ← Go module with wireguard-go pinned
    ios/
      PacketTunnelProvider.swift ← iOS/macOS NetworkExtension

scripts/
  build_linux.sh      ← Produces native/prebuilt/linux/libwireguard.so
  build_windows.sh    ← Produces native/prebuilt/windows/wireguard.dll + wintun.dll  
  build_android.sh    ← Produces 4× libwireguard.so for arm64/armeabi/x86/x86_64
  build_apple.sh      ← Produces WireGuard.xcframework (iOS device + Sim + macOS)

lib/
  engine/
    vpn_core_ffi.dart ← Dart FFI bridge (loads .so/.dll/.dylib, binds all C symbols)
    vpn_engine.dart   ← VpnEngine controller (state streams, telemetry, platform dispatch)
    vpn_config_builder.dart ← wg-quick config string builder
  models/
    vpn_models.dart   ← VpnState, VpnMetrics, VpnConfig value types
  ui/
    dashboard_screen.dart ← Premium dark-mode dashboard

android/app/src/main/kotlin/com/amitb/vpn/
  WireGuardVpnService.kt ← Android VpnService managing TUN fd
  VpnPlugin.kt           ← MethodChannel + EventChannel to pass fd to Dart

test/
  vpn_engine_unit_test.dart ← 13 passing unit tests
```

---

## Step 1: Build the Native Libraries

### Linux
```bash
chmod +x scripts/build_linux.sh
bash scripts/build_linux.sh
# Output: native/prebuilt/linux/libwireguard.so
```

### Windows (run from Linux with mingw64, or MSYS2 on Windows)
```bash
bash scripts/build_windows.sh
# Output: native/prebuilt/windows/wireguard.dll + wintun.dll
```

### Android (requires Android NDK r25c+)
```bash
export ANDROID_NDK_HOME=/path/to/ndk
bash scripts/build_android.sh
# Output: native/prebuilt/android/{arm64-v8a,...}/libwireguard.so
```

### iOS / macOS (requires macOS + Xcode)
```bash
bash scripts/build_apple.sh
# Output: native/prebuilt/apple/WireGuard.xcframework
```

---

## Step 2: Place Prebuilt Libraries

| Platform | File Location |
|---|---|
| Linux | Place `libwireguard.so` next to the binary, or add to LD_LIBRARY_PATH |
| Windows | Place `wireguard.dll` + `wintun.dll` in `windows/runner/` |
| Android | Place ABI folders under `android/app/src/main/jniLibs/` |
| iOS/macOS | Link `WireGuard.xcframework` in Xcode project → Frameworks |

---

## Step 3: Configure & Run

Edit `lib/ui/dashboard_screen.dart` and replace the placeholder keys:

```dart
final _config = const VpnConfig(
  privateKey:      'YOUR_DEVICE_PRIVATE_KEY',        // Curve25519, base64
  address:         '10.66.66.2/32',                  // Assigned by your backend
  serverPublicKey: 'YOUR_SERVER_PUBLIC_KEY',          // From your WireGuard server
  endpoint:        'your.vpn.server.com:51820',       // Server IP:port
  allowedIPs:      '0.0.0.0/0, ::/0',                // Full-tunnel
  dns:             '1.1.1.1',
);
```

Then run:
```bash
# Windows (must run as Administrator for Wintun)
flutter run -d windows

# Android
flutter run -d <device_id>
```

---

## Step 4: Run Unit Tests

```bash
flutter test test/vpn_engine_unit_test.dart --reporter expanded
# ✅ All 13 tests pass
```

---

## Key Design Decisions

| Decision | Rationale |
|---|---|
| **CGO `buildmode=c-shared`** | Produces a fully self-contained shared lib. No system WireGuard tools installed by users. |
| **Dart FFI over MethodChannel** | Direct Dart → C call has zero JNI/platform overhead and gives sub-100µs latency. |
| **Android VpnService fd passthrough** | Android mandates `VpnService.Builder` for TUN adapter creation. We grab the fd and hand it to the native core. |
| **iOS static framework** | Apple forbids dynamic-link privacy bypasses; static linking into the NE extension is required. |
| **UAPI internal protocol for stats** | WireGuard's `IpcGetOperation()` returns live Rx/Tx counters without a separate socket. |

---

## ⚠️ Administrator / Root Requirement

| Platform | Why |
|---|---|
| Windows | Creating a Wintun virtual adapter requires SYSTEM privileges |
| Linux | Creating `/dev/net/tun` requires `CAP_NET_ADMIN` |
| Android | Handled by Android OS via the VPN permission dialog |
| iOS/macOS | Handled by Apple via NetworkExtension entitlement |
