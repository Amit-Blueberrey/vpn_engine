# VPN Engine – Flutter WireGuard Package

A production-grade WireGuard VPN engine for Flutter.
Supports Android, iOS, macOS, Windows, and Linux via native platform channels.

---

## Package Versions (March 2026)

| Package | Version |
|---|---|
| flutter_riverpod | ^3.1.0 |
| riverpod | ^3.1.0 |
| provider | ^6.1.2 |
| dio | ^5.8.0+1 |
| http | ^1.3.0 |
| flutter_secure_storage | ^9.2.4 |
| cryptography | ^2.7.0 |
| pointycastle | ^3.9.1 |
| connectivity_plus | ^6.1.4 |
| device_info_plus | ^11.2.0 |
| package_info_plus | ^8.3.0 |
| fl_chart | ^0.69.0 |
| lottie | ^3.3.1 |
| logger | ^2.5.0 |
| talker_flutter | ^4.9.0 |
| shared_preferences | ^2.5.3 |
| intl | ^0.20.2 |
| uuid | ^4.5.1 |
| gap | ^3.0.1 |

> **Riverpod 3.x note:** `ChangeNotifierProvider` moved to the legacy import.
> In your Dart files, import it as:
> ```dart
> import 'package:flutter_riverpod/legacy.dart';
> ```

---

## How the Engine Works

```
Flutter UI
    │
    ▼
VpnEngineService  (ChangeNotifier)
    │  manages lifecycle, reconnect, key storage
    ▼
VpnPlatformChannel  (singleton)
    │  MethodChannel: com.vpnengine/wireguard
    │  EventChannels: vpn_state, traffic_log, dns_log
    ▼
Native Layer  (Android Java / iOS Swift / Windows C++ / Linux C)
    │  WireGuard-go / WireGuardKit / wireguard-windows
    ▼
OS WireGuard Tunnel
```

The `VpnConfig` model maps directly to a `wg-quick` config file:
```ini
[Interface]
PrivateKey = <device private key>    ← generated & stored on-device
Address    = 10.66.0.2/32
DNS        = 1.1.1.1, 1.0.0.1
MTU        = 1420

[Peer]
PublicKey           = <server public key>   ← YOU provide this
Endpoint            = vpn.example.com:51820  ← YOU provide this
AllowedIPs          = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
```

---

## Quick Start

### Step 1 – Get dependencies
```bash
cd vpn_engine
flutter pub get
```

### Step 2 – Generate device key pair (in the app)
Tap **Gen Keys** on the main screen.  
The private key is stored in the secure enclave (Keychain / Keystore).  
Copy the **public key** and register it with your WireGuard server.

### Step 3 – Fill in the Config tab
Open the **Config** tab (gear icon) and enter:

| Field | Where to get it |
|---|---|
| Server Endpoint | Your server IP/hostname + port, e.g. `vpn.example.com:51820` |
| Server Public Key | Run `wg show` on the server → copy the `public key` line |
| Tunnel IPv4 | IP assigned to this client by the server admin, e.g. `10.66.0.2/32` |
| Tunnel IPv6 | Optional IPv6 address, e.g. `fd42::2/128` |
| DNS Servers | `1.1.1.1, 1.0.0.1` or your private DNS |
| Preshared Key | Optional extra PSK if the server configured one |

### Step 4 – Connect
Tap the big **Connect** button.  
The engine will request VPN OS permission if needed, then activate the tunnel.

---

## Programmatic Usage (Production)

In production you'd fetch the server config from your backend API.  
Replace `_buildConfigFromInputs()` in `home_screen.dart` with:

```dart
Future<VpnConfig?> fetchConfigFromBackend() async {
  final vpn = ref.read(vpnServiceProvider);

  // 1. Ensure device has a key pair
  final hasKeys = await vpn.getSavedPublicKey() != null;
  if (!hasKeys) {
    final keys = await vpn.generateKeyPair();
    // POST keys['publicKey'] to your backend to register this device
    await myApiService.registerDevice(publicKey: keys['publicKey']!);
  }

  final privateKey = await vpn.getSavedPrivateKey();

  // 2. Fetch VPN config from backend (backend returns server's public key,
  //    the endpoint, and the tunnel IP assigned to this device)
  final cfg = await myApiService.getVpnConfig(region: selectedRegion);

  return VpnConfig(
    tunnelName: 'MyVPN',
    privateKey: privateKey!,               // from secure storage
    address: cfg.tunnelIpv4,              // from backend
    serverPublicKey: cfg.serverPublicKey, // from backend
    serverEndpoint: cfg.endpoint,         // from backend
    dnsServers: cfg.dnsServers,           // from backend
    allowedIPs: ['0.0.0.0/0', '::/0'],
  );
}
```

---

## VpnConfig fields reference

```dart
VpnConfig(
  tunnelName: 'VPNEngine',          // name shown in OS VPN settings
  privateKey: privateKey,           // Base64 Curve25519 — device private key
  address: '10.66.0.2/32',          // assigned tunnel IPv4
  addressV6: 'fd42::2/128',         // optional assigned tunnel IPv6
  dnsServers: ['1.1.1.1'],          // DNS servers used inside the tunnel
  mtu: 1420,                        // MTU (default 1420)
  serverPublicKey: serverPubKey,    // server's Curve25519 public key
  presharedKey: null,               // optional PSK
  serverEndpoint: 'host:51820',     // server host:port
  allowedIPs: ['0.0.0.0/0','::/0'],// full tunnel
  persistentKeepalive: 25,          // seconds (recommended for NAT)
)
```

---

## VpnEngineService API

```dart
// Read the service
final vpn = ref.watch(vpnServiceProvider);  // or ref.read()

// Connect
final result = await vpn.connect(config);   // returns VpnConnectResult
if (!result.success) print(result.message);

// Disconnect
await vpn.disconnect();

// Key management
final keys = await vpn.generateKeyPair();   // {privateKey, publicKey}
final pubKey = await vpn.getSavedPublicKey();
final privKey = await vpn.getSavedPrivateKey();

// State
print(vpn.status.state);        // VpnState enum
print(vpn.isConnected);         // bool
print(vpn.stats.formattedRx);   // e.g. "1.23MB"
print(vpn.stats.rxRateBps);     // bytes/sec

// Ping
final ms = await vpn.ping('vpn.example.com', 51820);

// Auto-reconnect
vpn.setAutoReconnect(true);

// Browsing/DNS log
await vpn.refreshBrowsingLog();
await vpn.clearBrowsingLog();
```

---

## Platform Integration

See `INSTRUCTIONS.md` for full step-by-step native wiring for:
- **Android** – WireGuard-Go JNI `.so` files, VpnService, `onActivityResult`
- **iOS** – WireGuardKit SPM, Network Extension, App Groups entitlements
- **Windows** – WireGuard CLI / embeddable DLL, CMakeLists.txt
- **Linux** – `wireguard-tools`, pkexec polkit, CMakeLists.txt
- **macOS** – similar to iOS Network Extension flow

---

## Project Structure

```
lib/
├── main.dart                      ← app entry + global Riverpod providers
├── core/
│   └── vpn_platform_channel.dart  ← ALL native ↔ Flutter communication
├── models/
│   ├── vpn_config.dart            ← WireGuard config model
│   ├── vpn_status.dart            ← VpnState enum + VpnStatus model
│   └── traffic_stats.dart         ← traffic/DNS/browsing log models
├── services/
│   ├── vpn_engine_service.dart    ← high-level VPN lifecycle service
│   └── key_manager.dart           ← WireGuard key secure storage
├── utils/
│   └── vpn_logger.dart            ← structured logger
└── ui/
    ├── screens/
    │   ├── home_screen.dart        ← SAMPLE APP  ← start here
    │   └── log_screen.dart         ← debug log viewer
    └── widgets/
        ├── connect_button.dart
        ├── status_card.dart
        ├── traffic_stats_card.dart
        └── browsing_log_widget.dart
```
