import 'package:get_storage/get_storage.dart';
import 'package:flutter/foundation.dart';
import '../models/vpn_models.dart';

class ServerRepository extends ChangeNotifier {
  static const String _storageKey = 'saved_servers';
  
  // Singleton
  ServerRepository._();
  static final ServerRepository instance = ServerRepository._();

  final List<SavedServer> _servers = [];
  List<SavedServer> get servers => List.unmodifiable(_servers);

  final _box = GetStorage();

  Future<void> init() async {
    final List<dynamic>? list = _box.read(_storageKey);
    if (list != null) {
      try {
        _servers.clear();
        _servers.addAll(list.map((e) => SavedServer.fromJson(Map<String, dynamic>.from(e))));
        notifyListeners();
      } catch (e) {
        print('Error loading servers: $e');
      }
    }
    
    // Default AWS server if none saved
    if (_servers.isEmpty) {
      const defaultServer = SavedServer(
        id: 'default-aws',
        name: 'AWS Primary',
        country: 'USA',
        flagEmoji: '🇺🇸',
        config: VpnConfig(
          privateKey: 'iLrG/EQBjRup1+2SeCJvYtSsvav+TU/hAsWBNwy77n4=',
          address: '10.0.0.2/32',
          serverPublicKey: 'cZ93r7NSXews2TScm8pPaBbGXb+knj6xIlldYEXaaAc=',
          endpoint: '3.238.201.203:51820',
          allowedIPs: '0.0.0.0/0',
          dns: '1.1.1.1',
          autoFallback: true,
          relayUrl: 'wss://3.238.201.203:443',
          relayToken: 'secret-vantage-relay-2026',
        ),
      );
      _servers.add(defaultServer);
      await save();
      notifyListeners();
    }
  }

  Future<void> addServer(SavedServer server) async {
    // Check for duplicates by endpoint
    if (_servers.any((s) => s.config.endpoint == server.config.endpoint)) {
      return; 
    }
    _servers.add(server);
    await save();
    notifyListeners();
  }

  Future<void> removeServer(String id) async {
    _servers.removeWhere((s) => s.id == id);
    await save();
    notifyListeners();
  }

  Future<void> save() async {
    await _box.write(_storageKey, _servers.map((s) => s.toJson()).toList());
  }
}
