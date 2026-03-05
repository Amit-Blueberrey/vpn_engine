// lib/models/vpn_config.dart
// ─────────────────────────────────────────────────────────────────────────────
// WireGuard configuration model – matches the wg-quick config format.
// This is what gets sent to the native layer for tunnel creation.
// ─────────────────────────────────────────────────────────────────────────────

class VpnConfig {
  // [Interface] section
  final String tunnelName;         // e.g. "VPNEngine"
  final String privateKey;         // Base64 Curve25519 private key (device)
  final String address;            // Assigned tunnel IP e.g. "10.66.0.2/32"
  final String? addressV6;         // IPv6 tunnel IP e.g. "fd42::2/128"
  final List<String> dnsServers;   // e.g. ["1.1.1.1", "1.0.0.1"]
  final int mtu;                   // default 1420

  // [Peer] section
  final String serverPublicKey;    // Server Curve25519 public key (Base64)
  final String? presharedKey;      // Optional extra PSK for post-quantum hardening
  final String serverEndpoint;     // "hostname:port" or "IP:port"
  final List<String> allowedIPs;   // "0.0.0.0/0, ::/0" for full tunnel
  final int? persistentKeepalive;  // seconds (25 recommended for NAT)

  const VpnConfig({
    required this.tunnelName,
    required this.privateKey,
    required this.address,
    this.addressV6,
    required this.dnsServers,
    this.mtu = 1420,
    required this.serverPublicKey,
    this.presharedKey,
    required this.serverEndpoint,
    required this.allowedIPs,
    this.persistentKeepalive = 25,
  });

  Map<String, dynamic> toMap() => {
        'tunnelName': tunnelName,
        'privateKey': privateKey,
        'address': address,
        'addressV6': addressV6,
        'dnsServers': dnsServers,
        'mtu': mtu,
        'serverPublicKey': serverPublicKey,
        'presharedKey': presharedKey,
        'serverEndpoint': serverEndpoint,
        'allowedIPs': allowedIPs,
        'persistentKeepalive': persistentKeepalive,
      };

  factory VpnConfig.fromMap(Map<String, dynamic> map) => VpnConfig(
        tunnelName: map['tunnelName'] as String,
        privateKey: map['privateKey'] as String,
        address: map['address'] as String,
        addressV6: map['addressV6'] as String?,
        dnsServers: List<String>.from(map['dnsServers'] as List),
        mtu: map['mtu'] as int? ?? 1420,
        serverPublicKey: map['serverPublicKey'] as String,
        presharedKey: map['presharedKey'] as String?,
        serverEndpoint: map['serverEndpoint'] as String,
        allowedIPs: List<String>.from(map['allowedIPs'] as List),
        persistentKeepalive: map['persistentKeepalive'] as int?,
      );

  /// Build a standard wg-quick formatted config string
  String toWgQuickFormat() {
    final buf = StringBuffer();
    buf.writeln('[Interface]');
    buf.writeln('PrivateKey = $privateKey');
    buf.writeln('Address = $address${addressV6 != null ? ", $addressV6" : ""}');
    buf.writeln('DNS = ${dnsServers.join(", ")}');
    buf.writeln('MTU = $mtu');
    buf.writeln();
    buf.writeln('[Peer]');
    buf.writeln('PublicKey = $serverPublicKey');
    if (presharedKey != null) buf.writeln('PresharedKey = $presharedKey');
    buf.writeln('Endpoint = $serverEndpoint');
    buf.writeln('AllowedIPs = ${allowedIPs.join(", ")}');
    if (persistentKeepalive != null) {
      buf.writeln('PersistentKeepalive = $persistentKeepalive');
    }
    return buf.toString();
  }

  VpnConfig copyWith({
    String? tunnelName,
    String? privateKey,
    String? address,
    String? addressV6,
    List<String>? dnsServers,
    int? mtu,
    String? serverPublicKey,
    String? presharedKey,
    String? serverEndpoint,
    List<String>? allowedIPs,
    int? persistentKeepalive,
  }) =>
      VpnConfig(
        tunnelName: tunnelName ?? this.tunnelName,
        privateKey: privateKey ?? this.privateKey,
        address: address ?? this.address,
        addressV6: addressV6 ?? this.addressV6,
        dnsServers: dnsServers ?? this.dnsServers,
        mtu: mtu ?? this.mtu,
        serverPublicKey: serverPublicKey ?? this.serverPublicKey,
        presharedKey: presharedKey ?? this.presharedKey,
        serverEndpoint: serverEndpoint ?? this.serverEndpoint,
        allowedIPs: allowedIPs ?? this.allowedIPs,
        persistentKeepalive: persistentKeepalive ?? this.persistentKeepalive,
      );
}

/// Full tunnel preset – routes all traffic through VPN
VpnConfig fullTunnelPreset({
  required String tunnelName,
  required String privateKey,
  required String address,
  required String serverPublicKey,
  required String serverEndpoint,
  String? addressV6,
  String? presharedKey,
}) =>
    VpnConfig(
      tunnelName: tunnelName,
      privateKey: privateKey,
      address: address,
      addressV6: addressV6,
      dnsServers: const ['1.1.1.1', '1.0.0.1'],
      serverPublicKey: serverPublicKey,
      presharedKey: presharedKey,
      serverEndpoint: serverEndpoint,
      allowedIPs: const ['0.0.0.0/0', '::/0'],
      persistentKeepalive: 25,
    );
