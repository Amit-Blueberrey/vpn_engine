/// test/vpn_engine_unit_test.dart
///
/// Unit tests for the VPN Engine layer (no native FFI calls made).
/// These tests exercise the Dart-level logic: config building,
/// model formatting, state transitions, and stream behavior.

// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_engine/engine/vpn_config_builder.dart';
import 'package:vpn_engine/models/vpn_models.dart';

void main() {
  // ────────────────────────────────────────────────────────────────────────────
  // Config Builder Tests
  // ────────────────────────────────────────────────────────────────────────────
  group('VpnConfigBuilder', () {
    test('builds minimal config correctly', () {
      final cfg = VpnConfigBuilder.buildString(
        privateKey:  'priv+key/base64+paddingAAAA=',
        address:     '10.66.66.2/32',
        publicKey:   'pub+key/base64+padAAAA=',
        endpoint:    '198.51.100.1:51820',
        allowedIPs:  '0.0.0.0/0',
      );
      expect(cfg, contains('[Interface]'));
      expect(cfg, contains('PrivateKey = priv+key/base64+paddingAAAA='));
      expect(cfg, contains('Address = 10.66.66.2/32'));
      expect(cfg, contains('[Peer]'));
      expect(cfg, contains('PublicKey = pub+key/base64+padAAAA='));
      expect(cfg, contains('Endpoint = 198.51.100.1:51820'));
      expect(cfg, contains('AllowedIPs = 0.0.0.0/0'));
      expect(cfg, contains('PersistentKeepalive = 25'));
      print('✅ Minimal config OK');
    });

    test('includes DNS and MTU when supplied', () {
      final cfg = VpnConfigBuilder.buildString(
        privateKey: 'priv', address: '10.0.0.1/24',
        publicKey:  'pub',  endpoint: '1.2.3.4:51820',
        allowedIPs: '0.0.0.0/0',
        dns: '8.8.8.8',
        mtu: 1380,
      );
      expect(cfg, contains('DNS = 8.8.8.8'));
      expect(cfg, contains('MTU = 1380'));
      print('✅ DNS + MTU OK');
    });

    test('includes PresharedKey when supplied', () {
      final cfg = VpnConfigBuilder.buildString(
        privateKey: 'priv', address: '10.0.0.1/24',
        publicKey:  'pub',  endpoint: '1.2.3.4:51820',
        allowedIPs: '0.0.0.0/0',
        presharedKey: 'psk_base64=',
      );
      expect(cfg, contains('PresharedKey = psk_base64='));
      print('✅ PresharedKey OK');
    });

    test('omits DNS when null', () {
      final cfg = VpnConfigBuilder.buildString(
        privateKey: 'p', address: '10.0.0.2/32',
        publicKey:  'q', endpoint: '1.1.1.1:51820',
        allowedIPs: '0.0.0.0/0',
        dns: null,
      );
      expect(cfg, isNot(contains('DNS')));
      print('✅ DNS omitted when null OK');
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // VpnConfig Model Tests
  // ────────────────────────────────────────────────────────────────────────────
  group('VpnConfig.toWgQuickConfig', () {
    test('generates a full WireGuard config block', () {
      const config = VpnConfig(
        privateKey:      'myPrivKey',
        address:         '10.66.66.2/32',
        serverPublicKey: 'serverPubKey',
        endpoint:        '1.2.3.4:51820',
        allowedIPs:      '0.0.0.0/0, ::/0',
        dns:             '1.1.1.1',
        mtu:             1420,
        tunnelName:      'wg0',
      );

      final wgCfg = config.toWgQuickConfig();

      expect(wgCfg, contains('[Interface]'));
      expect(wgCfg, contains('Address = 10.66.66.2/32'));
      expect(wgCfg, contains('[Peer]'));
      expect(wgCfg, contains('Endpoint = 1.2.3.4:51820'));
      print('✅ VpnConfig.toWgQuickConfig OK');
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // VpnMetrics Formatting Tests
  // ────────────────────────────────────────────────────────────────────────────
  group('VpnMetrics byte formatting', () {
    test('formats bytes correctly', () {
      final b = VpnMetrics(
          rxBytes: 512, txBytes: 512,
          rxPackets: 5, txPackets: 5,
          timestamp: DateTime.now());
      expect(b.rxFormatted, '512 B');
      print('✅ Bytes format OK');
    });

    test('formats KB correctly', () {
      final m = VpnMetrics(
          rxBytes: 2048, txBytes: 2048,
          rxPackets: 0, txPackets: 0,
          timestamp: DateTime.now());
      expect(m.rxFormatted, '2.0 KB');
      print('✅ KB format OK');
    });

    test('formats MB correctly', () {
      final m = VpnMetrics(
          rxBytes: 5 * 1024 * 1024, txBytes: 1,
          rxPackets: 0, txPackets: 0,
          timestamp: DateTime.now());
      expect(m.rxFormatted, '5.00 MB');
      print('✅ MB format OK');
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // VpnState → Native int mapping
  // ────────────────────────────────────────────────────────────────────────────
  group('VpnState.fromNative', () {
    test('maps 0 → disconnected', () {
      expect(VpnStateFromInt.fromNative(0), VpnState.disconnected);
      print('✅ 0 = disconnected');
    });
    test('maps 1 → connecting', () {
      expect(VpnStateFromInt.fromNative(1), VpnState.connecting);
      print('✅ 1 = connecting');
    });
    test('maps 2 → connected', () {
      expect(VpnStateFromInt.fromNative(2), VpnState.connected);
      print('✅ 2 = connected');
    });
    test('maps 3 → disconnecting', () {
      expect(VpnStateFromInt.fromNative(3), VpnState.disconnecting);
      print('✅ 3 = disconnecting');
    });
    test('maps unknown → error', () {
      expect(VpnStateFromInt.fromNative(99), VpnState.error);
      print('✅ invalid → error');
    });
  });
}
