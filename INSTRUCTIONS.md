# Step-by-Step Integration Instructions
> Follow these in order. Each section is self-contained per platform.

---

## STEP 1 – Get Flutter dependencies

```bash
cd vpn_engine
flutter pub get
```

---

## STEP 2 – Android Integration

### 2a. Wire onActivityResult in MainActivity.java

Open android/app/src/main/java/com/vpnengine/MainActivity.java
Add after onCreate / configureFlutterEngine:

```java
@Override
protected void onActivityResult(int requestCode, int resultCode, Intent data) {
    super.onActivityResult(requestCode, resultCode, data);
    if (methodHandler != null) {
        methodHandler.onActivityResult(requestCode, resultCode, data);
    }
}
```

### 2b. Get the WireGuard-Go native libraries

Download the latest wireguard-android AAR or source from:
https://github.com/WireGuard/wireguard-android/releases

Extract the .so files and place them at:
android/app/src/main/jniLibs/arm64-v8a/libwg-go.so
android/app/src/main/jniLibs/armeabi-v7a/libwg-go.so
android/app/src/main/jniLibs/x86_64/libwg-go.so

### 2c. Uncomment WireGuardKit in build.gradle

In android/app/build.gradle, uncomment:
  implementation 'com.wireguard.android:tunnel:1.0.20230706'

### 2d. Replace mock in WireGuardTunnel.java

In the start() method, the wgTurnOn() JNI call will now work with the .so in place.
Remove the UnsatisfiedLinkError catch block if desired (or keep as fallback for CI).

### 2e. Build and run on a PHYSICAL Android device

```bash
flutter run -d <android_device_id>
```
VPN does NOT work in an emulator without special network setup.

---

## STEP 3 – iOS Integration

### 3a. Open ios/ in Xcode

```bash
cd ios
open Runner.xcworkspace
```

### 3b. Add WireGuardKit via Swift Package Manager

- Xcode menu: File > Add Package Dependencies
- URL: https://github.com/WireGuard/wireguard-apple
- Add WireGuardKit to the TunnelExtension target ONLY (not Runner)

### 3c. Create the Packet Tunnel Provider target

- File > New > Target
- Select: Network Extension
- Product Name: TunnelExtension
- Bundle Identifier: com.vpnengine.tunnel
- Language: Swift

### 3d. Replace generated PacketTunnelProvider.swift

Delete the auto-generated one and add our file:
ios/TunnelExtension/PacketTunnelProvider.swift

In PacketTunnelProvider.swift, uncomment:
- import WireGuardKit
- The WireGuardAdapter lines in startTunnel()
- The adapter?.stop call in stopTunnel()

### 3e. Add App Group to both targets

- Runner target > Signing & Capabilities > + Capability > App Groups
- Add: group.com.vpnengine
- Repeat for TunnelExtension target

### 3f. Add Network Extensions capability

- Runner target > Signing & Capabilities > + Capability > Network Extensions
- Check "Packet Tunnel"
- Repeat for TunnelExtension

### 3g. Set TunnelExtension principal class

In TunnelExtension Info.plist:
NSExtension > NSExtensionPrincipalClass = $(PRODUCT_MODULE_NAME).PacketTunnelProvider

### 3h. Fix import in VpnEventChannelHandler.swift

Move the CryptoKit import to a separate file or the top of the file outside the struct.

### 3i. Run on a physical iOS device

Simulator does NOT support VPN extensions.

---

## STEP 4 – Windows Integration

### 4a. Install WireGuard

Download from https://www.wireguard.com/install/ and install.

### 4b. Register the plugin in flutter_window.cpp

Open windows/runner/flutter_window.cpp, add:

```cpp
#include "vpn_channel.h"
// In CreateAndShow() after registrar setup:
vpn_engine::VpnChannel::RegisterWithRegistrar(registrar);
```

### 4c. Add to CMakeLists.txt

In windows/runner/CMakeLists.txt, add:

```cmake
target_sources(${BINARY_NAME} PRIVATE
    "flutter_window.cpp"
    "main.cpp"
    "utils.cpp"
    "win32_window.cpp"
    "vpn_channel.cpp"   # ← add this
)
target_link_libraries(${BINARY_NAME} PRIVATE
    flutter
    flutter_wrapper_app
    bcrypt
    ws2_32
    shell32
)
```

### 4d. Replace stub connectWireGuard()

For a real tunnel, replace the stub with:

```cpp
// Write config to temp file then run:
std::string cmd = "wireguard.exe /installtunnelservice C:\\path\\to\\vpnengine.conf";
system(cmd.c_str());
```

Or use the embeddable DLL API directly:
https://git.zx2c4.com/wireguard-windows/about/embeddable-dll-service/

### 4e. Build

```bash
flutter run -d windows
```
May require running as Administrator the first time for driver installation.

---

## STEP 5 – Linux Integration

### 5a. Install wireguard-tools

```bash
sudo apt install wireguard    # Debian/Ubuntu
sudo dnf install wireguard-tools  # Fedora
```

### 5b. Register the plugin in my_application.cc

Open linux/runner/my_application.cc, add:

```c
#include "vpn_channel.h"
// In my_application_activate():
FlPluginRegistry* registry = fl_engine_get_plugin_registry(engine);
vpn_channel_register(registry);
```

### 5c. Add to CMakeLists.txt

In linux/runner/CMakeLists.txt:

```cmake
target_sources(${BINARY_NAME} PRIVATE
    "main.cc"
    "my_application.cc"
    "vpn_channel.cc"   # ← add this
)
```

### 5d. Build and run

```bash
flutter run -d linux
```

The connect() call uses pkexec for elevation. You'll see a polkit dialog on first connect.

---

## STEP 6 – Backend API Wiring (optional but needed for production)

In lib/ui/screens/home_screen.dart, replace _buildDemoConfig() with:

```dart
Future<VpnConfig> fetchConfigFromBackend() async {
  // 1. Get/generate keys
  final vpn = context.read<VpnEngineService>();
  final hasKeys = await vpn._keyManager.hasKeyPair();
  if (!hasKeys) {
    final keys = await vpn.generateKeyPair();
    // POST keys['publicKey'] to POST /devices/register
    await myApiService.registerDevice(publicKey: keys['publicKey']!);
  }
  final privateKey = await vpn.getSavedPrivateKey();
  
  // 2. Get VPN config from backend
  final response = await myApiService.getVpnConfig(regionId: selectedRegion);
  
  return VpnConfig(
    tunnelName: 'MyVPN',
    privateKey: privateKey!,
    address: response.tunnelIpv4,
    serverPublicKey: response.serverPublicKey,
    serverEndpoint: response.endpoint,
    allowedIPs: ['0.0.0.0/0', '::/0'],
    dnsServers: response.dnsServers,
  );
}
```

---

## TROUBLESHOOTING

### "VPN permission denied" on Android
- Make sure the onActivityResult() is wired (Step 2a)
- Test on a real device, not emulator

### "wgTurnOn returned -1" on Android
- The libwg-go.so files are missing or wrong ABI
- Check: adb shell getprop ro.product.cpu.abi

### "TUN interface could not be established" on Android
- VpnService.prepare() was not called, or returned non-null
- The VPN permission flow didn't complete

### iOS: "Failed to save VPN config"
- App Group is not configured or doesn't match
- Network Extension capability not added

### Linux: "wg-quick failed"
- wireguard-tools not installed
- pkexec/polkit not available: try running with sudo instead

### Windows: "ConnectWireGuard failed"
- Run as Administrator
- WireGuard not installed at default path

