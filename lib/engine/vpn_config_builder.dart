class VpnConfigBuilder {
  static String buildString({
    required String privateKey,
    required String address,
    required String publicKey,
    required String endpoint,
    required String allowedIPs,
    String? dns,
    String? presharedKey,
    int? mtu,
  }) {
    final buffer = StringBuffer();
    
    // [Interface]
    buffer.writeln('[Interface]');
    buffer.writeln('PrivateKey = $privateKey');
    buffer.writeln('Address = $address');
    if (dns != null && dns.isNotEmpty) {
      buffer.writeln('DNS = $dns');
    }
    if (mtu != null) {
      buffer.writeln('MTU = $mtu');
    }
    
    buffer.writeln('');
    
    // [Peer]
    buffer.writeln('[Peer]');
    buffer.writeln('PublicKey = $publicKey');
    if (presharedKey != null && presharedKey.isNotEmpty) {
      buffer.writeln('PresharedKey = $presharedKey');
    }
    buffer.writeln('Endpoint = $endpoint');
    buffer.writeln('AllowedIPs = $allowedIPs');
    buffer.writeln('PersistentKeepalive = 25'); // Standard keepalive

    return buffer.toString();
  }
}
