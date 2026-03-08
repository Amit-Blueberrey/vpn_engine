# Flutter Native WireGuard Engine

A production-grade, highly scalable WireGuard VPN integration for Flutter platforms (Windows focus).

## Architecture Approach
Instead of recompiling `wireguard-go` or `Wintun.dll` completely from scratch (which takes weeks of cross-platform low-level C codebase wrangling and maintaining bindings), this engine acts as a **Thin Platform Glue**, wrapping the industry-standard `wireguard_flutter` package. 

This approach uses official WireGuard tools under the hood:
* **Android:** Official `VpnService` using `wireguard-go` via `wg-quick` semantics.
* **iOS/macOS:** Apple's `NetworkExtension` Framework using `WireGuardKit`.
* **Windows:** The official `wireguard-nt` or Wintun driver. 

## Features
- Full async support for Connection State Changes (`VpnEngine.vpnStage`).
- Config Builder (`VpnConfigBuilder`) to dynamically construct `wg-quick` configurations for peers.
- No OpenVPN dependencies—pure, fast WireGuard.
- Provider-based state management structure.

## How to Test
1. Make sure you are on Windows. Run `flutter clean` then `flutter pub get`.
2. Open `lib/main.dart` and insert actual WireGuard Private Key, Public Key, and Server Endpoints from a live WireGuard server (such as your own backend).
3. Run `flutter run -d windows` (Requires Administrator Privileges for Wintun to attach the adapter successfully).

## Note on "Viewing Webpage Links"
WireGuard operates at IP level (Layer 3). It routes low-level network packets (`0.0.0.0/0`) over an encrypted UDP tunnel to the server. The client device and Server **cannot inherently read individual "webpage links" (HTTP URLs)**. Doing so requires advanced, custom Deep Packet Inspection (DPI) and Man-In-The-Middle TLS proxying, which violates standard store policies for VPN apps.

Instead, the `wireguard_flutter` and typical VPN models provide network interface statistics (total Tx/Rx bytes sent/received), connection logs, and tunnel status, which are integrated here.
