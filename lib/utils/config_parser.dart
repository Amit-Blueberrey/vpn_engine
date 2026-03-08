import '../models/vpn_models.dart';

class ConfigParser {
  /// Parses a WireGuard .conf content string into a VpnConfig object.
  /// Bulletproof: Strips comments, handles variations in spacing, 
  /// and is case-insensitive.
  static VpnConfig? parse(String content) {
    if (content.isEmpty) return null;

    final lines = content.split('\n');
    final Map<String, String> values = {};
    
    // Simple state machine to track if we're in [Interface] or [Peer]
    // though for simple WireGuard configs we can just grab all keys.
    for (var line in lines) {
      // Strip comments (starting with # or ;)
      final cleanLine = line.split('#')[0].split(';')[0].trim();
      if (cleanLine.isEmpty || cleanLine.startsWith('[')) continue;

      final parts = cleanLine.split('=');
      if (parts.length < 2) continue;

      final key = parts[0].trim().toLowerCase();
      // Join remaining parts in case the value itself contains an =
      final value = parts.sublist(1).join('=').trim();
      
      values[key] = value;
    }

    // Extract required fields
    final privateKey = values['privatekey'];
    final address = values['address'];
    final publicKey = values['publickey'];
    final endpoint = values['endpoint'];
    
    // AllowedIPs often defaults to 0.0.0.0/0 if missing in vpn contexts
    final allowedIPs = values['allowedips'] ?? '0.0.0.0/0';
    final dns = values['dns'];
    final presharedKey = values['presharedkey'];
    final mtu = int.tryParse(values['mtu'] ?? '') ?? 1420;

    if (privateKey != null && address != null && publicKey != null && endpoint != null) {
      return VpnConfig(
        privateKey: privateKey,
        address: address,
        serverPublicKey: publicKey,
        endpoint: endpoint,
        allowedIPs: allowedIPs,
        dns: dns,
        presharedKey: presharedKey,
        mtu: mtu,
      );
    }

    return null;
  }
}
