/// vpn_models.dart
///
/// Immutable value types shared by the FFI Bridge and the UI layer.

enum VpnState {
  disconnected,
  connecting,
  connected,
  disconnecting,
  error,
}

/// Converts the C integer WgTunnelState into a [VpnState].
VpnState vpnStateFromNative(int v) {
  switch (v) {
    case 0: return VpnState.disconnected;
    case 1: return VpnState.connecting;
    case 2: return VpnState.connected;
    case 3: return VpnState.disconnecting;
    default: return VpnState.error;
  }
}

// Keep old name as thin alias so vpn_engine.dart doesn't need changing.
// ignore: camel_case_types
abstract class VpnStateFromInt {
  static VpnState fromNative(int v) => vpnStateFromNative(v);
}


/// Real-time bandwidth snapshot emitted every second.
class VpnMetrics {
  final int rxBytes;
  final int txBytes;
  final int rxPackets;
  final int txPackets;
  final DateTime timestamp;

  const VpnMetrics({
    required this.rxBytes,
    required this.txBytes,
    required this.rxPackets,
    required this.txPackets,
    required this.timestamp,
  });

  factory VpnMetrics.zero() => VpnMetrics(
        rxBytes: 0, txBytes: 0,
        rxPackets: 0, txPackets: 0,
        timestamp: DateTime.now(),
      );

  String get rxFormatted => _format(rxBytes);
  String get txFormatted => _format(txBytes);

  static String _format(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    } else if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    } else if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }

  @override
  String toString() =>
      'VpnMetrics(↓${rxFormatted} ↑${txFormatted} @ $timestamp)';
}

/// Represents the current configuration passed to the engine.
class VpnConfig {
  final String privateKey;
  final String address;
  final String serverPublicKey;
  final String endpoint;
  final String allowedIPs;
  final String? dns;
  final String? presharedKey;
  final int mtu;
  final String tunnelName;

  const VpnConfig({
    required this.privateKey,
    required this.address,
    required this.serverPublicKey,
    required this.endpoint,
    required this.allowedIPs,
    this.dns,
    this.presharedKey,
    this.mtu = 1420,
    this.tunnelName = 'wg0',
    this.autoFallback = false,
    this.relayUrl = '',
    this.relayToken = '',
  });

  /// [autoFallback]: if true, the engine will use WebSocket relay if UDP is blocked.
  final bool autoFallback;
  final String relayUrl;
  final String relayToken;

  /// Renders the canonical wg-quick configuration block.
  String toWgQuickConfig() {
    final buf = StringBuffer();
    buf.writeln('[Interface]');
    buf.writeln('PrivateKey = $privateKey');
    buf.writeln('Address = $address');
    if (dns != null) buf.writeln('DNS = $dns');
    buf.writeln('MTU = $mtu');
    buf.writeln();
    buf.writeln('[Peer]');
    buf.writeln('PublicKey = $serverPublicKey');
    if (presharedKey != null) buf.writeln('PresharedKey = $presharedKey');
    buf.writeln('Endpoint = $endpoint');
    buf.writeln('AllowedIPs = $allowedIPs');
    buf.writeln('PersistentKeepalive = 25');
    return buf.toString();
  }

  Map<String, dynamic> toJson() => {
        'privateKey': privateKey,
        'address': address,
        'serverPublicKey': serverPublicKey,
        'endpoint': endpoint,
        'allowedIPs': allowedIPs,
        'dns': dns,
        'presharedKey': presharedKey,
        'mtu': mtu,
        'tunnelName': tunnelName,
        'autoFallback': autoFallback,
        'relayUrl': relayUrl,
        'relayToken': relayToken,
      };

  factory VpnConfig.fromJson(Map<String, dynamic> json) => VpnConfig(
        privateKey: json['privateKey'] as String,
        address: json['address'] as String,
        serverPublicKey: json['serverPublicKey'] as String,
        endpoint: json['endpoint'] as String,
        allowedIPs: json['allowedIPs'] as String,
        dns: json['dns'] as String?,
        presharedKey: json['presharedKey'] as String?,
        mtu: json['mtu'] as int? ?? 1420,
        tunnelName: json['tunnelName'] as String? ?? 'wg0',
        autoFallback: json['autoFallback'] as bool? ?? false,
        relayUrl: json['relayUrl'] as String? ?? '',
        relayToken: json['relayToken'] as String? ?? '',
      );
}

/// Represents a server saved in the user's list.
class SavedServer {
  final String id;
  final String name;
  final String country;
  final String flagEmoji;
  final VpnConfig config;
  final int? latencyMs;

  const SavedServer({
    required this.id,
    required this.name,
    required this.country,
    required this.flagEmoji,
    required this.config,
    this.latencyMs,
  });

  SavedServer copyWith({int? latencyMs}) => SavedServer(
        id: id,
        name: name,
        country: country,
        flagEmoji: flagEmoji,
        config: config,
        latencyMs: latencyMs ?? this.latencyMs,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'country': country,
        'flagEmoji': flagEmoji,
        'config': config.toJson(),
      };

  factory SavedServer.fromJson(Map<String, dynamic> json) => SavedServer(
        id: json['id'] as String,
        name: json['name'] as String,
        country: json['country'] as String,
        flagEmoji: json['flagEmoji'] as String,
        config: VpnConfig.fromJson(json['config'] as Map<String, dynamic>),
      );
}
