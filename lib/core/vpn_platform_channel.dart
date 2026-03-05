// lib/core/vpn_platform_channel.dart
// ─────────────────────────────────────────────────────────────────────────────
// CENTRAL PLATFORM CHANNEL BRIDGE
// All native ↔ Flutter communication goes through this single file.
// Channel name: com.vpnengine/wireguard
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/services.dart';
import '../models/vpn_config.dart';
import '../models/vpn_status.dart';
import '../models/traffic_stats.dart';
import '../utils/vpn_logger.dart';

/// All method names used across Android / iOS / macOS / Windows / Linux
class _Methods {
  static const initialize        = 'initialize';
  static const connect           = 'connect';
  static const disconnect        = 'disconnect';
  static const getStatus         = 'getStatus';
  static const getTrafficStats   = 'getTrafficStats';
  static const generateKeyPair   = 'generateKeyPair';
  static const importConfig      = 'importConfig';
  static const removeConfig      = 'removeConfig';
  static const isPermissionGranted = 'isPermissionGranted';
  static const requestPermission  = 'requestPermission';
  static const checkTunInterface  = 'checkTunInterface';
  static const getActiveInterface = 'getActiveInterface';
  static const listPeers          = 'listPeers';
  static const getBrowsingLog     = 'getBrowsingLog';      // DNS + traffic log
  static const clearBrowsingLog   = 'clearBrowsingLog';
  static const setDnsServers      = 'setDnsServers';
  static const pingServer         = 'pingServer';
}

/// Event channel names
class _Events {
  static const vpnState   = 'com.vpnengine/vpn_state';
  static const trafficLog = 'com.vpnengine/traffic_log';
  static const dnsLog     = 'com.vpnengine/dns_log';
}

/// ────────────────────────────────────────────────────────────────────────────
/// VpnPlatformChannel  –  Singleton that owns all channel interactions
/// ────────────────────────────────────────────────────────────────────────────
class VpnPlatformChannel {
  // ── Channels ──────────────────────────────────────────────────────────────
  static const MethodChannel _methodChannel =
      MethodChannel('com.vpnengine/wireguard');

  static const EventChannel _stateChannel =
      EventChannel(_Events.vpnState);

  static const EventChannel _trafficLogChannel =
      EventChannel(_Events.trafficLog);

  static const EventChannel _dnsLogChannel =
      EventChannel(_Events.dnsLog);

  // ── Singleton ─────────────────────────────────────────────────────────────
  VpnPlatformChannel._();
  static final VpnPlatformChannel instance = VpnPlatformChannel._();

  // ── Streams (broadcast) ───────────────────────────────────────────────────
  late final Stream<VpnStatus> vpnStateStream = _stateChannel
      .receiveBroadcastStream()
      .map((event) => VpnStatus.fromMap(Map<String, dynamic>.from(event as Map)))
      .handleError((e) => VpnLogger.error('VPN state stream error: $e'))
      .asBroadcastStream();

  late final Stream<TrafficLogEntry> trafficLogStream = _trafficLogChannel
      .receiveBroadcastStream()
      .map((e) => TrafficLogEntry.fromMap(Map<String, dynamic>.from(e as Map)))
      .handleError((e) => VpnLogger.error('Traffic log stream error: $e'))
      .asBroadcastStream();

  late final Stream<DnsLogEntry> dnsLogStream = _dnsLogChannel
      .receiveBroadcastStream()
      .map((e) => DnsLogEntry.fromMap(Map<String, dynamic>.from(e as Map)))
      .handleError((e) => VpnLogger.error('DNS log stream error: $e'))
      .asBroadcastStream();

  // ══════════════════════════════════════════════════════════════════════════
  // METHOD IMPLEMENTATIONS
  // ══════════════════════════════════════════════════════════════════════════

  /// Initialize the native WireGuard engine (call once at app start).
  Future<bool> initialize() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>(_Methods.initialize);
      VpnLogger.info('Native engine initialized: $result');
      return result ?? false;
    } on PlatformException catch (e) {
      VpnLogger.error('initialize() failed: ${e.message}');
      return false;
    }
  }

  /// Connect using the given WireGuard config.
  Future<VpnConnectResult> connect(VpnConfig config) async {
    try {
      VpnLogger.info('Connecting to ${config.serverEndpoint}...');
      final result = await _methodChannel.invokeMethod<Map>(
        _Methods.connect,
        config.toMap(),
      );
      final r = VpnConnectResult.fromMap(Map<String, dynamic>.from(result!));
      VpnLogger.info('Connect result: ${r.success} | ${r.message}');
      return r;
    } on PlatformException catch (e) {
      VpnLogger.error('connect() PlatformException: ${e.code} - ${e.message}');
      return VpnConnectResult(success: false, message: e.message ?? 'Unknown error');
    } catch (e) {
      VpnLogger.error('connect() error: $e');
      return VpnConnectResult(success: false, message: e.toString());
    }
  }

  /// Disconnect active tunnel.
  Future<bool> disconnect() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>(_Methods.disconnect);
      VpnLogger.info('Disconnect result: $result');
      return result ?? false;
    } on PlatformException catch (e) {
      VpnLogger.error('disconnect() failed: ${e.message}');
      return false;
    }
  }

  /// Get current VPN status (state, tunnel IP, uptime, etc.)
  Future<VpnStatus> getStatus() async {
    try {
      final result = await _methodChannel.invokeMethod<Map>(_Methods.getStatus);
      return VpnStatus.fromMap(Map<String, dynamic>.from(result!));
    } on PlatformException catch (e) {
      VpnLogger.error('getStatus() failed: ${e.message}');
      return VpnStatus.disconnected();
    }
  }

  /// Get current traffic statistics (bytes in/out, packets, etc.)
  Future<TrafficStats> getTrafficStats() async {
    try {
      final result =
          await _methodChannel.invokeMethod<Map>(_Methods.getTrafficStats);
      return TrafficStats.fromMap(Map<String, dynamic>.from(result!));
    } on PlatformException catch (e) {
      VpnLogger.error('getTrafficStats() failed: ${e.message}');
      return TrafficStats.empty();
    }
  }

  /// Generate a WireGuard Curve25519 keypair via native crypto.
  /// Returns {privateKey: base64, publicKey: base64}
  Future<Map<String, String>> generateKeyPair() async {
    try {
      final result =
          await _methodChannel.invokeMethod<Map>(_Methods.generateKeyPair);
      return Map<String, String>.from(result!);
    } on PlatformException catch (e) {
      VpnLogger.error('generateKeyPair() failed: ${e.message}');
      rethrow;
    }
  }

  /// Import a WireGuard config (stores it in the OS tunnel profile).
  Future<bool> importConfig(VpnConfig config) async {
    try {
      final result = await _methodChannel.invokeMethod<bool>(
        _Methods.importConfig,
        config.toMap(),
      );
      return result ?? false;
    } on PlatformException catch (e) {
      VpnLogger.error('importConfig() failed: ${e.message}');
      return false;
    }
  }

  /// Remove a saved config / profile from the OS.
  Future<bool> removeConfig(String tunnelName) async {
    try {
      final result = await _methodChannel.invokeMethod<bool>(
        _Methods.removeConfig,
        {'tunnelName': tunnelName},
      );
      return result ?? false;
    } on PlatformException catch (e) {
      VpnLogger.error('removeConfig() failed: ${e.message}');
      return false;
    }
  }

  /// Check if VpnService (Android) / NetworkExtension (iOS) permission granted.
  Future<bool> isPermissionGranted() async {
    try {
      final result =
          await _methodChannel.invokeMethod<bool>(_Methods.isPermissionGranted);
      return result ?? false;
    } on PlatformException catch (e) {
      VpnLogger.error('isPermissionGranted() failed: ${e.message}');
      return false;
    }
  }

  /// Request OS VPN permission (Android: VpnService intent, iOS: NEVPNManager).
  Future<bool> requestPermission() async {
    try {
      final result =
          await _methodChannel.invokeMethod<bool>(_Methods.requestPermission);
      return result ?? false;
    } on PlatformException catch (e) {
      VpnLogger.error('requestPermission() failed: ${e.message}');
      return false;
    }
  }

  /// Check if tun interface is up and active.
  Future<bool> checkTunInterface() async {
    try {
      final result =
          await _methodChannel.invokeMethod<bool>(_Methods.checkTunInterface);
      return result ?? false;
    } on PlatformException catch (e) {
      return false;
    }
  }

  /// Get current active WireGuard interface name (e.g., 'wg0').
  Future<String?> getActiveInterface() async {
    try {
      return await _methodChannel.invokeMethod<String>(_Methods.getActiveInterface);
    } on PlatformException catch (e) {
      VpnLogger.error('getActiveInterface() failed: ${e.message}');
      return null;
    }
  }

  /// List all registered WireGuard peers from the active interface.
  Future<List<Map<String, dynamic>>> listPeers() async {
    try {
      final result =
          await _methodChannel.invokeMethod<List>(_Methods.listPeers);
      return result?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
    } on PlatformException catch (e) {
      VpnLogger.error('listPeers() failed: ${e.message}');
      return [];
    }
  }

  /// Fetch the in-memory browsing/DNS log from the native layer.
  Future<List<BrowsingLogEntry>> getBrowsingLog() async {
    try {
      final result =
          await _methodChannel.invokeMethod<List>(_Methods.getBrowsingLog);
      return result
              ?.map((e) =>
                  BrowsingLogEntry.fromMap(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          [];
    } on PlatformException catch (e) {
      VpnLogger.error('getBrowsingLog() failed: ${e.message}');
      return [];
    }
  }

  /// Clear the browsing log on the native side.
  Future<void> clearBrowsingLog() async {
    try {
      await _methodChannel.invokeMethod(_Methods.clearBrowsingLog);
    } on PlatformException catch (e) {
      VpnLogger.error('clearBrowsingLog() failed: ${e.message}');
    }
  }

  /// Override DNS servers on the active tunnel.
  Future<bool> setDnsServers(List<String> dnsServers) async {
    try {
      final result = await _methodChannel.invokeMethod<bool>(
        _Methods.setDnsServers,
        {'dnsServers': dnsServers},
      );
      return result ?? false;
    } on PlatformException catch (e) {
      VpnLogger.error('setDnsServers() failed: ${e.message}');
      return false;
    }
  }

  /// Ping a VPN server endpoint to check latency (ms). Returns -1 on failure.
  Future<int> pingServer(String host, int port) async {
    try {
      final result = await _methodChannel.invokeMethod<int>(
        _Methods.pingServer,
        {'host': host, 'port': port},
      );
      return result ?? -1;
    } on PlatformException catch (e) {
      VpnLogger.error('pingServer() failed: ${e.message}');
      return -1;
    }
  }
}
