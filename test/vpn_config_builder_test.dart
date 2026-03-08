import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_engine_app/engine/vpn_config_builder.dart';

void main() {
  group('VpnConfigBuilder Tests', () {
    test('Builds basic config correctly', () {
      final config = VpnConfigBuilder.buildString(
        privateKey: 'private_key_test',
        address: '10.0.0.2/32',
        publicKey: 'public_key_test',
        endpoint: '198.51.100.1:51820',
        allowedIPs: '0.0.0.0/0',
      );

      // Interface block
      expect(config, contains('[Interface]'));
      expect(config, contains('PrivateKey = private_key_test'));
      expect(config, contains('Address = 10.0.0.2/32'));

      // Peer block
      expect(config, contains('[Peer]'));
      expect(config, contains('PublicKey = public_key_test'));
      expect(config, contains('Endpoint = 198.51.100.1:51820'));
      expect(config, contains('AllowedIPs = 0.0.0.0/0'));
      expect(config, contains('PersistentKeepalive = 25'));
    });

    test('Builds config with optional parameters', () {
      final config = VpnConfigBuilder.buildString(
        privateKey: 'private_key',
        address: '10.0.0.2/32',
        publicKey: 'public_key',
        endpoint: '198.51.100.1:51820',
        allowedIPs: '0.0.0.0/0',
        dns: '1.1.1.1',
        mtu: 1420,
        presharedKey: 'preshared_test',
      );

      expect(config, contains('DNS = 1.1.1.1'));
      expect(config, contains('MTU = 1420'));
      expect(config, contains('PresharedKey = preshared_test'));
    });
  });
}
