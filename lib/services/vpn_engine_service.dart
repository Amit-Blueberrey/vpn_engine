// lib/services/vpn_engine_service.dart
// ─────────────────────────────────────────────────────────────────────────────
// VPN Engine Service
// High-level service that wraps VpnPlatformChannel with:
//  - connection lifecycle management
//  - auto-reconnect logic
//  - stats polling
//  - key management
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/foundation.dart';
import '../core/vpn_platform_channel.dart';
import '../models/vpn_config.dart';
import '../models/vpn_status.dart';
import '../models/traffic_stats.dart';
import '../utils/vpn_logger.dart';
import 'key_manager.dart';

class VpnEngineService extends ChangeNotifier {
  final VpnPlatformChannel _channel = VpnPlatformChannel.instance;
  final KeyManager _keyManager = KeyManager();

  // ── State ─────────────────────────────────────────────────────────────────
  VpnStatus _status = VpnStatus.disconnected();
  TrafficStats _stats = TrafficStats.empty();
  VpnConfig? _currentConfig;
  bool _initialized = false;
  bool _autoReconnect = true;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;

  // Browsing log (live, in-memory)
  final List<BrowsingLogEntry> _browsingLog = [];
  final List<DnsLogEntry> _dnsLog = [];
  final List<TrafficLogEntry> _trafficLog = [];

  // ── Subscriptions ─────────────────────────────────────────────────────────
  StreamSubscription<VpnStatus>? _stateSub;
  StreamSubscription<TrafficLogEntry>? _trafficSub;
  StreamSubscription<DnsLogEntry>? _dnsSub;
  Timer? _statsPollTimer;
  Timer? _reconnectTimer;

  // ── Getters ───────────────────────────────────────────────────────────────
  VpnStatus get status => _status;
  TrafficStats get stats => _stats;
  VpnConfig? get currentConfig => _currentConfig;
  bool get isConnected => _status.isConnected;
  bool get isConnecting => _status.isConnecting;
  bool get autoReconnect => _autoReconnect;
  List<BrowsingLogEntry> get browsingLog => List.unmodifiable(_browsingLog);
  List<DnsLogEntry> get dnsLog => List.unmodifiable(_dnsLog);
  List<TrafficLogEntry> get trafficLog => List.unmodifiable(_trafficLog);

  // ── Initialization ────────────────────────────────────────────────────────

  Future<void> initialize() async {
    if (_initialized) return;
    VpnLogger.info('Initializing VPN engine service...');

    // Init native engine
    final ok = await _channel.initialize();
    if (!ok) {
      VpnLogger.error('Native engine failed to initialize');
      return;
    }

    // Subscribe to state events from native
    _stateSub = _channel.vpnStateStream.listen(
      _onStateChange,
      onError: (e) => VpnLogger.error('State stream error: $e'),
    );

    // Subscribe to traffic log stream
    _trafficSub = _channel.trafficLogStream.listen(
      (entry) {
        _trafficLog.insert(0, entry);
        if (_trafficLog.length > 500) _trafficLog.removeLast();
        notifyListeners();
      },
      onError: (e) => VpnLogger.error('Traffic log stream error: $e'),
    );

    // Subscribe to DNS log stream
    _dnsSub = _channel.dnsLogStream.listen(
      (entry) {
        _dnsLog.insert(0, entry);
        if (_dnsLog.length > 1000) _dnsLog.removeLast();
        notifyListeners();
      },
      onError: (e) => VpnLogger.error('DNS log stream error: $e'),
    );

    // Start stats polling every 1 second when connected
    _statsPollTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (_status.isConnected) {
        _stats = await _channel.getTrafficStats();
        notifyListeners();
      }
    });

    _initialized = true;
    VpnLogger.info('VPN engine service initialized');
    notifyListeners();
  }

  // ── Connection Lifecycle ──────────────────────────────────────────────────

  /// Full connect flow:
  /// 1. Check/request VPN permission
  /// 2. Import config into OS tunnel profile
  /// 3. Activate tunnel
  Future<VpnConnectResult> connect(VpnConfig config) async {
    VpnLogger.info('connect() called → ${config.serverEndpoint}');
    _reconnectAttempts = 0;
    _currentConfig = config;

    // 1. Permission
    final hasPermission = await _channel.isPermissionGranted();
    if (!hasPermission) {
      VpnLogger.info('Requesting VPN permission...');
      final granted = await _channel.requestPermission();
      if (!granted) {
        VpnLogger.warn('VPN permission denied by user');
        return const VpnConnectResult(
          success: false,
          message: 'VPN permission was denied. Please grant it in system settings.',
        );
      }
    }

    // 2. Update status → connecting
    _setStatus(VpnStatus(
      state: VpnState.connecting,
      serverEndpoint: config.serverEndpoint,
    ));

    // 3. Connect via native
    final result = await _channel.connect(config);
    if (!result.success) {
      _setStatus(VpnStatus(
        state: VpnState.error,
        errorMessage: result.message,
      ));
      VpnLogger.error('Native connect failed: ${result.message}');
    } else {
      VpnLogger.info('Native connect succeeded');
    }

    return result;
  }

  Future<bool> disconnect() async {
    VpnLogger.info('disconnect() called');
    _autoReconnect = false; // disable reconnect on manual disconnect
    _reconnectTimer?.cancel();

    _setStatus(VpnStatus(
      state: VpnState.disconnecting,
      serverEndpoint: _currentConfig?.serverEndpoint,
    ));

    final ok = await _channel.disconnect();
    if (ok) {
      _currentConfig = null;
      _setStatus(VpnStatus.disconnected());
    }
    return ok;
  }

  void setAutoReconnect(bool value) {
    _autoReconnect = value;
    notifyListeners();
  }

  // ── Key management (delegate to KeyManager) ───────────────────────────────

  Future<Map<String, String>> generateKeyPair() async {
    VpnLogger.info('Generating new WireGuard keypair...');
    final keys = await _channel.generateKeyPair();
    await _keyManager.saveKeyPair(
      privateKey: keys['privateKey']!,
      publicKey: keys['publicKey']!,
    );
    VpnLogger.info('Keypair generated and saved. Public: ${keys['publicKey']}');
    return keys;
  }

  Future<String?> getSavedPublicKey() => _keyManager.getPublicKey();
  Future<String?> getSavedPrivateKey() => _keyManager.getPrivateKey();

  // ── Browsing Log ──────────────────────────────────────────────────────────

  Future<void> refreshBrowsingLog() async {
    final entries = await _channel.getBrowsingLog();
    _browsingLog
      ..clear()
      ..addAll(entries.reversed);
    notifyListeners();
  }

  Future<void> clearBrowsingLog() async {
    await _channel.clearBrowsingLog();
    _browsingLog.clear();
    _dnsLog.clear();
    _trafficLog.clear();
    notifyListeners();
  }

  // ── Ping ──────────────────────────────────────────────────────────────────

  Future<int> ping(String host, int port) => _channel.pingServer(host, port);

  // ── Private helpers ───────────────────────────────────────────────────────

  void _onStateChange(VpnStatus newStatus) {
    VpnLogger.info('State change → ${newStatus.state}');
    _setStatus(newStatus);

    if (newStatus.state == VpnState.error ||
        newStatus.state == VpnState.disconnected) {
      if (_autoReconnect &&
          _currentConfig != null &&
          _reconnectAttempts < _maxReconnectAttempts) {
        _scheduleReconnect();
      }
    }
  }

  void _scheduleReconnect() {
    _reconnectAttempts++;
    final delay = Duration(seconds: _reconnectAttempts * 2);
    VpnLogger.warn(
      'Scheduling reconnect attempt $_reconnectAttempts in ${delay.inSeconds}s',
    );
    _setStatus(VpnStatus(
      state: VpnState.reconnecting,
      serverEndpoint: _currentConfig?.serverEndpoint,
    ));
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () async {
      if (_currentConfig != null && _autoReconnect) {
        await _channel.connect(_currentConfig!);
      }
    });
  }

  void _setStatus(VpnStatus s) {
    _status = s;
    notifyListeners();
  }

  // ── Dispose ───────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _stateSub?.cancel();
    _trafficSub?.cancel();
    _dnsSub?.cancel();
    _statsPollTimer?.cancel();
    _reconnectTimer?.cancel();
    super.dispose();
  }
}
