// lib/services/key_manager.dart
// ─────────────────────────────────────────────────────────────────────────────
// Secure key storage using flutter_secure_storage.
// Private keys NEVER leave the device unencrypted.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../utils/vpn_logger.dart';

class KeyManager {
  static const _kPrivateKey = 'wg_private_key';
  static const _kPublicKey  = 'wg_public_key';
  static const _kDeviceId   = 'device_id';

  final FlutterSecureStorage _store = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  Future<void> saveKeyPair({
    required String privateKey,
    required String publicKey,
  }) async {
    await Future.wait([
      _store.write(key: _kPrivateKey, value: privateKey),
      _store.write(key: _kPublicKey, value: publicKey),
    ]);
    VpnLogger.debug('Keypair saved to secure storage');
  }

  Future<String?> getPrivateKey() => _store.read(key: _kPrivateKey);
  Future<String?> getPublicKey()  => _store.read(key: _kPublicKey);

  Future<bool> hasKeyPair() async {
    final priv = await getPrivateKey();
    final pub  = await getPublicKey();
    return priv != null && pub != null;
  }

  Future<void> deleteKeyPair() async {
    await Future.wait([
      _store.delete(key: _kPrivateKey),
      _store.delete(key: _kPublicKey),
    ]);
    VpnLogger.info('Keypair deleted from secure storage');
  }

  Future<void> saveDeviceId(String id) =>
      _store.write(key: _kDeviceId, value: id);

  Future<String?> getDeviceId() => _store.read(key: _kDeviceId);

  Future<void> saveValue(String key, String value) =>
      _store.write(key: key, value: value);

  Future<String?> getValue(String key) => _store.read(key: key);

  Future<void> deleteValue(String key) => _store.delete(key: key);

  Future<void> clearAll() => _store.deleteAll();
}
