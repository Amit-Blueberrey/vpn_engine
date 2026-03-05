# TASK.md – VPN Engine Flutter Project
## Status: Core implementation complete. Integration steps required per platform.

---

## COMPLETED FILES

### Flutter/Dart
- lib/main.dart                          - App entry, Riverpod setup
- lib/core/vpn_platform_channel.dart     - Central MethodChannel + 3x EventChannels
- lib/models/vpn_config.dart             - WireGuard config model + wg-quick serializer
- lib/models/vpn_status.dart             - VPN state enum + status model
- lib/models/traffic_stats.dart          - TrafficStats, TrafficLogEntry, DnsLogEntry, BrowsingLogEntry
- lib/services/vpn_engine_service.dart   - High-level service: lifecycle, reconnect, log
- lib/services/key_manager.dart          - Secure key storage via flutter_secure_storage
- lib/utils/vpn_logger.dart              - In-memory logger, level filter, broadcast listeners
- lib/ui/screens/home_screen.dart        - Main VPN UI (connect/status/settings)
- lib/ui/screens/log_screen.dart         - Debug console (engine/traffic/DNS tabs)
- lib/ui/widgets/connect_button.dart     - Animated connect button with state colors
- lib/ui/widgets/status_card.dart        - Tunnel IP / endpoint / uptime display
- lib/ui/widgets/traffic_stats_card.dart - RX/TX bytes, packet counters
- lib/ui/widgets/browsing_log_widget.dart- Live browsing + DNS + traffic log

### Android (Java)
- android/.../MainActivity.java                        - Flutter activity
- android/.../channel/VpnMethodChannelHandler.java     - All 17 method handlers
- android/.../channel/VpnEventChannelHandler.java      - 3x EventChannels via BroadcastReceiver
- android/.../service/WireGuardVpnService.java         - VpnService foreground service + TUN
- android/.../tunnel/WireGuardTunnel.java              - wg-go JNI wrapper + mock fallback
- android/.../tunnel/PacketProcessor.java              - IPv4/IPv6/TCP/UDP packet parser
- android/.../utils/DnsInterceptor.java                - DNS wire-format parser + forwarder
- android/.../utils/KeyGeneratorUtil.java              - Pure-Java Curve25519 X25519
- android/.../utils/PingUtil.java                      - TCP connect latency
- android/.../model/WgConfig.java                      - Config model (Map + JSON)
- android/.../AndroidManifest.xml                      - VPN permissions + service declaration

### iOS (Swift)
- ios/Runner/AppDelegate.swift                  - Channel registration
- ios/Runner/VpnMethodChannelHandler.swift       - All method handling
- ios/Runner/VpnManager.swift                   - NETunnelProviderManager wrapper
- ios/Runner/VpnEventChannelHandler.swift        - 3x EventChannel StreamHandlers
- ios/TunnelExtension/PacketTunnelProvider.swift - NEPacketTunnelProvider extension

### Windows (C++)
- windows/runner/vpn_channel.h   - Plugin header
- windows/runner/vpn_channel.cpp - Full MethodChannel + 3x EventChannels + WireGuard stubs

### Linux (C)
- linux/runner/vpn_channel.h  - Header
- linux/runner/vpn_channel.cc - wg-quick integration + all channels

---

## INTEGRATION STEPS (must do before building)

### ANDROID
1. Download wireguard-android from: https://github.com/WireGuard/wireguard-android/releases
   - Copy libwg-go.so files to android/app/src/main/jniLibs/{arm64-v8a,armeabi-v7a,x86_64}/
   - Uncomment WireGuardKit dep in android/app/build.gradle

2. Wire VPN permission result in MainActivity.java:
   @Override
   protected void onActivityResult(int req, int res, Intent data) {
       super.onActivityResult(req, res, data);
       if (methodHandler != null) methodHandler.onActivityResult(req, res, data);
   }

3. Connect works on physical device only (not emulator).

### IOS
1. Open ios/ in Xcode
2. Add Package: https://github.com/WireGuard/wireguard-apple (WireGuardKit)
   - Add to TunnelExtension target only
3. Add new target: File > New > Target > Network Extension > Packet Tunnel
   - Bundle ID: com.vpnengine.tunnel
   - Set NSExtensionPrincipalClass = PacketTunnelProvider
4. Add App Group "group.com.vpnengine" to both targets
5. Enable Network Extensions capability in both targets
6. In PacketTunnelProvider.swift, uncomment WireGuardKit import + adapter lines

### WINDOWS
1. Install WireGuard: https://www.wireguard.com/install/
2. In windows/runner/flutter_window.cpp add:
   #include "vpn_channel.h"
   vpn_engine::VpnChannel::RegisterWithRegistrar(registrar);
3. Add to CMakeLists.txt:
   target_link_libraries(${BINARY_NAME} PRIVATE bcrypt ws2_32)
   add_subdirectory(runner)
4. For real tunneling: replace stub connectWireGuard() with wireguard.exe calls

### LINUX
1. In linux/runner/my_application.cc add:
   #include "vpn_channel.h"
   vpn_channel_register(registry);
2. In CMakeLists.txt add:
   target_sources(${BINARY_NAME} PRIVATE "runner/vpn_channel.cc")
3. Install wireguard-tools: sudo apt install wireguard

---

## CHANNEL CONTRACT

MethodChannel: com.vpnengine/wireguard
  initialize()                    -> bool
  connect(VpnConfig)              -> {success, message, assignedTunnelIp}
  disconnect()                    -> bool
  getStatus()                     -> VpnStatus map
  getTrafficStats()               -> TrafficStats map
  generateKeyPair()               -> {privateKey, publicKey}
  importConfig(VpnConfig)         -> bool
  removeConfig({tunnelName})      -> bool
  isPermissionGranted()           -> bool
  requestPermission()             -> bool
  checkTunInterface()             -> bool
  getActiveInterface()            -> String?
  listPeers()                     -> List<Map>
  getBrowsingLog()                -> List<BrowsingLogEntry>
  clearBrowsingLog()              -> void
  setDnsServers({dnsServers})     -> bool
  pingServer({host, port})        -> int (ms, -1=fail)

EventChannel: com.vpnengine/vpn_state   -> VpnStatus map (on change)
EventChannel: com.vpnengine/traffic_log -> TrafficLogEntry map (per connection)
EventChannel: com.vpnengine/dns_log     -> DnsLogEntry map (per DNS query)

---

## KNOWN GAPS / TODOs

1. iOS pubkey generation - generateWithCommonCrypto() uses reversed bytes as placeholder.
   Replace with: import CryptoKit; Curve25519.KeyAgreement.PrivateKey()
   (already written in generateWithCryptoKit(), just fix the import placement)

2. Windows/Linux traffic stats are simulated. Wire to:
   - Windows: WireGuardGetConfiguration() DLL call or parse wg show
   - Linux: parse "wg show vpnengine transfer" (already wired in cc file)

3. DNS browsing log on iOS/Windows/Linux: The tunnel extension must write DNS events
   to a shared App Group container. Wire PacketTunnelProvider DNS parsing + app group
   UserDefaults → read from VpnManager.getBrowsingLog()

4. Backend API integration: VpnEngineService.connect() currently accepts a manually
   built VpnConfig. Wire to your API: POST /vpn/config -> returns config JSON.

5. Key registration flow: After generateKeyPair(), send publicKey to backend
   POST /devices/register { device_public_key, platform, device_name }

---

## SECURITY NOTES

- Private keys stored in: Android Keystore (EncryptedSharedPreferences) / iOS Keychain
- Private keys NEVER leave the device unencrypted
- Config file on Linux created with chmod 0600
- Add Dio certificate pinning interceptor before shipping to production
- Implement key rotation in VpnEngineService (add rotateKeys() method)
