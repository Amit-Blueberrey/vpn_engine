/// vpn_engine.dart
///
/// Phase 4: The main VpnEngine controller.
///
/// This is the single public API that the Flutter UI touches.
/// It owns:
///   - The actual native tunnel handle
///   - Stream<VpnState>   – connection state changes
///   - Stream<VpnMetrics> – 1-second telemetry ticks
///
/// Platform dispatch:
///   Android   → sends config to the MethodChannel; receives fd via EventChannel,
///               then calls WireGuardCore.tunnelStart(config, fd: fd).
///   iOS/macOS → activates NEVPNManager via the SystemVpnManager helper.
///   Win/Linux → calls WireGuardCore.tunnelStart() directly (no fd needed).

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/vpn_models.dart';
import '../services/server_repository.dart';
import 'vpn_core_ffi.dart';

// ─── Platform channels (Android only) ────────────────────────────────────────

const _kMethodChannel = MethodChannel('com.amitb.vpn/engine');
const _kEventChannel  = EventChannel('com.amitb.vpn/tunnel_fd');

// ─── VpnEngine ────────────────────────────────────────────────────────────────

class VpnEngine extends ChangeNotifier {

  // ── Singleton ───────────────────────────────────────────────────────────────
  VpnEngine._();
  static final VpnEngine instance = VpnEngine._();

  // ── State ───────────────────────────────────────────────────────────────────
  VpnState _state = VpnState.disconnected;
  VpnState get state => _state;

  VpnMetrics _metrics = VpnMetrics.zero();
  VpnMetrics get metrics => _metrics;

  // Per-second speed (bytes/s) — computed as delta between polls
  double _speedRx = 0;
  double _speedTx = 0;
  double get speedRx => _speedRx;
  double get speedTx => _speedTx;

  // Rolling 30-second history for the sparkline chart
  final List<double> rxHistory = List.filled(30, 0);
  final List<double> txHistory = List.filled(30, 0);

  VpnMetrics? _prevMetrics;
  int _handle = -1;

  // Track the server being connected
  SavedServer? _pendingServer;

  // ── Streams ──────────────────────────────────────────────────────────────────
  final _stateController   = StreamController<VpnState>.broadcast();
  final _metricsController = StreamController<VpnMetrics>.broadcast();

  Stream<VpnState>   get stateStream   => _stateController.stream;
  Stream<VpnMetrics> get metricsStream => _metricsController.stream;
  Stream<String>     get nativeLogsStream => WireGuardCore.instance.nativeLogsStream;

  Timer? _pollTimer;
  StreamSubscription? _androidFdSub;

  // ── Connect ──────────────────────────────────────────────────────────────────

  Future<void> connect(VpnConfig config, {SavedServer? serverMetadata}) async {
    if (_state == VpnState.connected || _state == VpnState.connecting) return;
    _pendingServer = serverMetadata;
    _emitState(VpnState.connecting);
    _log('Connecting to ${config.endpoint}... (fallback=${config.autoFallback})');

    try {
      if (Platform.isAndroid) {
        await _connectAndroid(config);
      } else if (Platform.isIOS || Platform.isMacOS) {
        await _connectApple(config);
      } else {
        await _connectDirect(config);
      }
    } catch (e) {
      _log('Connect error: $e', isError: true);
      _emitState(VpnState.error);
    }
  }

  // ── Disconnect ──────────────────────────────────────────────────────────────

  Future<void> disconnect() async {
    if (_state == VpnState.disconnected) return;
    _emitState(VpnState.disconnecting);
    _log('Disconnecting...');
    _stopPoll();

    try {
      if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
        // Signal the platform; the native side will call wg_tunnel_stop.
        await _kMethodChannel.invokeMethod('stopVpn');
      } else {
        if (_handle >= 0) {
          WireGuardCore.instance.tunnelStopWithFallback(_handle);
          _handle = -1;
        }
      }
    } catch (e) {
      _log('Disconnect error: $e', isError: true);
    } finally {
      _emitState(VpnState.disconnected);
      _emitMetrics(VpnMetrics.zero());
    }
  }

  // ── Key generation ──────────────────────────────────────────────────────────

  /// Generates a Curve25519 private key directly via native FFI.
  String generatePrivateKey() {
    try {
      return WireGuardCore.instance.generatePrivateKey();
    } catch (e) {
      _log('keygen error: $e', isError: true);
      rethrow;
    }
  }

  String derivePublicKey(String privateKey) =>
      WireGuardCore.instance.derivePublicKey(privateKey);

  String generatePresharedKey() =>
      WireGuardCore.instance.generatePresharedKey();

  // ── Platform-specific internals ─────────────────────────────────────────────

  Future<void> _connectDirect(VpnConfig config) async {
    final cfgStr = config.toWgQuickConfig();
    try {
      if (config.autoFallback && config.relayUrl.isNotEmpty) {
        _log('UDP handshake start (fallback available via ${config.relayUrl})');
        _handle = WireGuardCore.instance.tunnelStartWithFallback(
          cfgStr,
          name: config.tunnelName,
          relayUrl: config.relayUrl,
          relayToken: config.relayToken,
          handshakeTimeoutSec: 10, // Increased for first-time wintun initialization
        );
      } else {
        _handle = WireGuardCore.instance.tunnelStart(cfgStr, name: config.tunnelName);
      }
      _log('Tunnel started, handle=$_handle');
      _emitState(VpnState.connected);
      _startPoll();
    } on WgException catch (e) {
      _log('Native WireGuard Error: ${e.message}', isError: true);
      _emitState(VpnState.error);
    } catch (e) {
      _log('Unexpected error: $e', isError: true);
      _emitState(VpnState.error);
    }
  }

  Future<void> _connectAndroid(VpnConfig config) async {
    // 1. Ask Android to grant VPN permission.
    final granted = await _kMethodChannel.invokeMethod<bool>('prepare');
    if (granted != true) {
      _log('VPN permission denied', isError: true);
      _emitState(VpnState.disconnected);
      return;
    }

    // 2. Subscribe to the EventChannel BEFORE starting the service.
    final completer = Completer<Map<dynamic, dynamic>>();
    _androidFdSub = _kEventChannel.receiveBroadcastStream().listen((event) {
      if (!completer.isCompleted) completer.complete(event as Map<dynamic, dynamic>);
    });

    // 3. Start the VpnService — it will call VpnService.Builder.establish()
    //    and push the fd into our EventChannel.
    await _kMethodChannel.invokeMethod('startVpn', {
      'config': config.toWgQuickConfig(),
      'dns':    config.dns ?? '1.1.1.1',
    });

    // 4. Wait for the fd (with timeout).
    final Map<dynamic, dynamic> payload = await completer.future
        .timeout(const Duration(seconds: 10));
    await _androidFdSub?.cancel();

    final fd     = (payload['fd'] as int?) ?? -1;
    final cfgStr = (payload['config'] as String?) ?? config.toWgQuickConfig();

    if (fd < 0) {
      _log('Invalid fd received from Android', isError: true);
      _emitState(VpnState.error);
      return;
    }

    // 5. Now we have the OS-sanctioned fd — hand it to the native core.
    _handle = WireGuardCore.instance.tunnelStart(cfgStr,
        name: config.tunnelName, fd: fd);
    _log('Android tunnel started, handle=$_handle, fd=$fd');
    _emitState(VpnState.connected);
    _startPoll();
  }

  Future<void> _connectApple(VpnConfig config) async {
    // iOS/macOS: the system NetworkExtension process handles wg_tunnel_start.
    // We only need to tell the main app to activate NEVPNManager.
    await _kMethodChannel.invokeMethod('startVpn', {
      'config': config.toWgQuickConfig(),
    });

    // State updates come via NEVPNStatusDidChange notifications forwarded
    // through the MethodChannel's event side. For simplicity we optimistically
    // move to connected; a full implementation would await the notification.
    _emitState(VpnState.connected);
    _startPoll();
  }

  // ── Telemetry polling ───────────────────────────────────────────────────────

  void _startPoll() {
    _pollTimer?.cancel();
    _prevMetrics = null;
    int successTicks = 0;

    _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_handle < 0) return;
      try {
        final m = WireGuardCore.instance.getMetrics(_handle);
        
        // Compute per-second deltas
        if (_prevMetrics != null) {
          _speedRx = (m.rxBytes - _prevMetrics!.rxBytes).toDouble().clamp(0, double.infinity);
          _speedTx = (m.txBytes - _prevMetrics!.txBytes).toDouble().clamp(0, double.infinity);
        } else {
          _speedRx = 0;
          _speedTx = 0;
        }

        // Logic for "Save on Success"
        if (_pendingServer != null && m.rxBytes > 0) {
          successTicks++;
          if (successTicks >= 2) { // 2 seconds of traffic verified
             ServerRepository.instance.addServer(_pendingServer!);
             _pendingServer = null; 
             _log('Connection verified. Server saved to local database.');
          }
        }

        _prevMetrics = m;
        // Rolling history
        rxHistory.removeAt(0); rxHistory.add(_speedRx);
        txHistory.removeAt(0); txHistory.add(_speedTx);
        _metrics = m;
        _emitMetrics(m);
      } catch (_) {}
    });
  }

  void _stopPoll() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  // ── Stream helpers ──────────────────────────────────────────────────────────

  void _emitState(VpnState s) {
    _state = s;
    _stateController.add(s);
    notifyListeners();
  }

  void _emitMetrics(VpnMetrics m) {
    _metricsController.add(m);
    notifyListeners();
  }

  // ── Logging (public for debug dashboard) ─────────────────────────────────────

  final List<String> logs = [];

  void addLog(String msg, {bool isError = false}) => _log(msg, isError: isError);

  void _log(String msg, {bool isError = false}) {
    final entry = '[${DateTime.now().toIso8601String()}] ${isError ? "ERROR" : "INFO"}: $msg';
    logs.add(entry);
    if (isError) debugPrint('\x1B[31m$entry\x1B[0m');
    else debugPrint(entry);
    notifyListeners();
  }

  // ── Debug Simulation Methods ─────────────────────────────────────────────────
  // These are TESTING ONLY methods consumed by DebugDashboard.

  void simulateFallbackTrigger() {
    _log('[SIM] UDP Block simulated — autoFallback would activate in 5s');
    _emitState(VpnState.connecting);
    Future.delayed(const Duration(seconds: 1), () {
      if (_state == VpnState.connecting) {
        _log('[SIM] Fallback triggered — in production TCP relay activates here');
        _emitState(VpnState.connected);
      }
    });
  }

  void simulateSleep() {
    _log('[SIM] Simulating CPU sleep — pausing poll for 5 seconds');
    _stopPoll();
    Future.delayed(const Duration(seconds: 5), () {
      _log('[SIM] Woke up from sleep — resuming poll');
      _startPoll();
    });
  }

  void simulateNetworkSwitch() {
    _log('[SIM] Wi-Fi → Cellular switch detected — triggering reconnect');
    if (_state == VpnState.connected) {
      _emitState(VpnState.connecting);
      Future.delayed(const Duration(seconds: 2), () {
        _log('[SIM] Reconnect complete after network switch');
        _emitState(VpnState.connected);
      });
    }
  }

  void simulateAbruptKill() {
    _log('[SIM] Abrupt kill — invalidating tunnel handle', isError: true);
    _stopPoll();
    _handle = -1;
    _emitState(VpnState.error);
  }

  @override
  void dispose() {
    _stopPoll();
    _stateController.close();
    _metricsController.close();
    super.dispose();
  }
}
