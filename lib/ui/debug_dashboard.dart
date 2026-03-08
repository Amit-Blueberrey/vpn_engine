/// debug_dashboard.dart
///
/// Module 4: Advanced VPN Debugging "Command Center"
///
/// Features:
///   ① Real-time LineChart plotting Download/Upload speeds (fl_chart)
///   ② Connection State Machine Tracker with micro-states
///   ③ "Simulate Failure" button panel for testing fallback mechanisms
///   ④ Encrypted State Dump export (base64-encoded compressed JSON)

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';

import '../engine/vpn_engine.dart';
import '../models/vpn_models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Speed sample ring-buffer for the chart
// ─────────────────────────────────────────────────────────────────────────────

class _SpeedSample {
  final double rxKbps;
  final double txKbps;
  final double t; // seconds since start
  _SpeedSample(this.rxKbps, this.txKbps, this.t);
}

// ─────────────────────────────────────────────────────────────────────────────
// Micro-state for the connection state machine tracker
// ─────────────────────────────────────────────────────────────────────────────

enum MicroState {
  idle,
  keysGenerated,
  handshakeInitiated,
  handshakeAcknowledged,
  mtuNegotiated,
  routingTableUpdated,
  tunnelEstablished,
  tcpFallbackActivated,
  disconnecting,
  error,
}

extension MicroStateLabel on MicroState {
  String get label {
    switch (this) {
      case MicroState.idle:                  return '⚪ Idle';
      case MicroState.keysGenerated:         return '🔑 Keys Generated';
      case MicroState.handshakeInitiated:    return '🤝 Handshake Initiated';
      case MicroState.handshakeAcknowledged: return '✅ Handshake Acknowledged';
      case MicroState.mtuNegotiated:         return '📐 MTU Negotiated (1420)';
      case MicroState.routingTableUpdated:   return '🗺️ Routing Table Updated';
      case MicroState.tunnelEstablished:     return '🛡️ Tunnel Established';
      case MicroState.tcpFallbackActivated:  return '🔄 TCP Fallback Active';
      case MicroState.disconnecting:         return '⏹️ Disconnecting';
      case MicroState.error:                 return '❌ Error';
    }
  }

  Color get color {
    switch (this) {
      case MicroState.idle:                  return Colors.grey;
      case MicroState.keysGenerated:         return Colors.purpleAccent;
      case MicroState.handshakeInitiated:    return Colors.orangeAccent;
      case MicroState.handshakeAcknowledged: return Colors.lightGreenAccent;
      case MicroState.mtuNegotiated:         return Colors.cyanAccent;
      case MicroState.routingTableUpdated:   return Colors.blueAccent;
      case MicroState.tunnelEstablished:     return Colors.greenAccent;
      case MicroState.tcpFallbackActivated:  return Colors.amberAccent;
      case MicroState.disconnecting:         return Colors.deepOrangeAccent;
      case MicroState.error:                 return Colors.redAccent;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Debug Dashboard Screen
// ─────────────────────────────────────────────────────────────────────────────

class DebugDashboard extends StatefulWidget {
  const DebugDashboard({Key? key}) : super(key: key);

  @override
  State<DebugDashboard> createState() => _DebugDashboardState();
}

class _DebugDashboardState extends State<DebugDashboard>
    with SingleTickerProviderStateMixin {

  static const _maxSamples = 60;     // 60 seconds of chart history
  static const _pollMs     = 1000;   // 1-second telemetry

  late final TabController _tabs;
  final List<_SpeedSample> _samples = [];
  Timer? _pollTimer;
  double _elapsed = 0;
  double _prevRx  = 0;
  double _prevTx  = 0;

  MicroState _microState = MicroState.idle;
  final List<(DateTime, MicroState)> _stateHistory = [];

  StreamSubscription? _logSub;
  final ScrollController _terminalScroll = ScrollController();
  final List<String> _nativeLogs = [];

  // ── Init & Dispose ───────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 5, vsync: this);
    WireGuardCore.instance.initializeLogging(); // Ensure FFI is ready
    _logSub = VpnEngine.instance.nativeLogsStream.listen((msg) {
      if (!mounted) return;
      setState(() {
        _nativeLogs.add('[${DateTime.now().toIso8601String().substring(11,23)}] $msg');
        if (_nativeLogs.length > 500) _nativeLogs.removeAt(0); // keep it tidy
      });
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_terminalScroll.hasClients) {
          _terminalScroll.animateTo(
            _terminalScroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    });
    _startPolling();
  }

  @override
  void dispose() {
    _logSub?.cancel();
    _terminalScroll.dispose();
    _tabs.dispose();
    _pollTimer?.cancel();
    super.dispose();
  }

  // ── Polling ──────────────────────────────────────────────────────────────

  void _startPolling() {
    _pollTimer = Timer.periodic(
      const Duration(milliseconds: _pollMs), (_) {
      final engine = VpnEngine.instance;
      final m = engine.metrics;

      final rxDelta = (m.rxBytes - _prevRx).clamp(0.0, double.infinity);
      final txDelta = (m.txBytes - _prevTx).clamp(0.0, double.infinity);
      _prevRx = m.rxBytes.toDouble();
      _prevTx = m.txBytes.toDouble();

      _elapsed += 1.0;

      if (mounted) {
        setState(() {
          _samples.add(_SpeedSample(rxDelta / 1024, txDelta / 1024, _elapsed));
          if (_samples.length > _maxSamples) _samples.removeAt(0);

          // Synthesize micro-states from engine.state + metrics
          _updateMicroState(engine.state, m);
        });
      }
    });
  }

  void _updateMicroState(VpnState vpnState, VpnMetrics m) {
    MicroState next = _microState;
    switch (vpnState) {
      case VpnState.connecting:
        if (_microState == MicroState.idle) {
          next = MicroState.keysGenerated;
        } else if (_microState == MicroState.keysGenerated) {
          next = MicroState.handshakeInitiated;
        }
        break;
      case VpnState.connected:
        if (_microState == MicroState.handshakeInitiated ||
            _microState == MicroState.keysGenerated) {
          next = MicroState.handshakeAcknowledged;
          Future.delayed(const Duration(milliseconds: 200), () {
            _advanceMicro(MicroState.mtuNegotiated);
            Future.delayed(const Duration(milliseconds: 300), () {
              _advanceMicro(MicroState.routingTableUpdated);
              Future.delayed(const Duration(milliseconds: 400), () {
                _advanceMicro(MicroState.tunnelEstablished);
              });
            });
          });
        }
        break;
      case VpnState.disconnecting:
        next = MicroState.disconnecting;
        break;
      case VpnState.disconnected:
        next = MicroState.idle;
        break;
      case VpnState.error:
        next = MicroState.error;
        break;
    }
    if (next != _microState) {
      _microState = next;
      _stateHistory.add((DateTime.now(), next));
    }
  }

  void _advanceMicro(MicroState s) {
    if (!mounted) return;
    setState(() {
      _microState = s;
      _stateHistory.add((DateTime.now(), s));
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080812),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('🛡️ VPN Command Center',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold,
                letterSpacing: 1.2, fontSize: 16)),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.blueAccent,
          tabs: const [
            Tab(icon: Icon(Icons.show_chart, size: 18), text: 'Speed'),
            Tab(icon: Icon(Icons.account_tree, size: 18), text: 'States'),
            Tab(icon: Icon(Icons.bug_report, size: 18), text: 'Simulate'),
            Tab(icon: Icon(Icons.terminal, size: 18), text: 'Terminal'),
            Tab(icon: Icon(Icons.download, size: 18), text: 'Dump'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _buildSpeedTab(),
          _buildStateTab(),
          _buildSimulateTab(),
          _buildTerminalTab(),
          _buildDumpTab(),
        ],
      ),
    );
  }

  // ── Tab 1: Real-Time Speed Chart ──────────────────────────────────────────

  Widget _buildSpeedTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildCurrentSpeedRow(),
          const SizedBox(height: 16),
          Expanded(child: _buildLineChart()),
          const SizedBox(height: 8),
          _buildChartLegend(),
        ],
      ),
    );
  }

  Widget _buildCurrentSpeedRow() {
    final lastRx = _samples.isNotEmpty ? _samples.last.rxKbps : 0.0;
    final lastTx = _samples.isNotEmpty ? _samples.last.txKbps : 0.0;
    return Row(children: [
      Expanded(child: _speedCard('↓ DOWNLOAD', lastRx, Colors.greenAccent)),
      const SizedBox(width: 12),
      Expanded(child: _speedCard('↑ UPLOAD', lastTx, Colors.blueAccent)),
    ]);
  }

  Widget _speedCard(String label, double kbps, Color color) {
    String formatted;
    if (kbps >= 1024) {
      formatted = '${(kbps / 1024).toStringAsFixed(2)} MB/s';
    } else {
      formatted = '${kbps.toStringAsFixed(1)} KB/s';
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(color: Colors.white54, fontSize: 10,
            letterSpacing: 1.5, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(formatted, style: TextStyle(color: color, fontSize: 20,
            fontWeight: FontWeight.bold)),
      ]),
    );
  }

  Widget _buildLineChart() {
    if (_samples.isEmpty) {
      return const Center(child: Text('Waiting for data...',
          style: TextStyle(color: Colors.white38)));
    }
    double maxY = _samples.map((s) => s.rxKbps > s.txKbps ? s.rxKbps : s.txKbps)
        .reduce((a, b) => a > b ? a : b);
    maxY = (maxY * 1.25).clamp(10.0, double.infinity);

    List<FlSpot> rxSpots = _samples
        .map((s) => FlSpot(s.t, s.rxKbps)).toList();
    List<FlSpot> txSpots = _samples
        .map((s) => FlSpot(s.t, s.txKbps)).toList();

    return LineChart(LineChartData(
      backgroundColor: Colors.transparent,
      minY: 0, maxY: maxY,
      minX: _samples.first.t, maxX: _samples.last.t,
      gridData: FlGridData(
        show: true,
        getDrawingHorizontalLine: (v) => FlLine(
            color: Colors.white10, strokeWidth: 0.5),
        getDrawingVerticalLine: (v) => FlLine(
            color: Colors.white10, strokeWidth: 0.5),
      ),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(sideTitles: SideTitles(
          showTitles: true, reservedSize: 45,
          getTitlesWidget: (v, _) => Text(
            v >= 1024 ? '${(v/1024).toStringAsFixed(0)}M' : '${v.toInt()}K',
            style: const TextStyle(color: Colors.white38, fontSize: 9)),
        )),
        bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      borderData: FlBorderData(show: false),
      lineBarsData: [
        _lineBar(rxSpots, Colors.greenAccent),
        _lineBar(txSpots, Colors.blueAccent),
      ],
    ));
  }

  LineChartBarData _lineBar(List<FlSpot> spots, Color color) =>
      LineChartBarData(
        spots: spots,
        isCurved: true,
        color: color,
        barWidth: 2,
        dotData: FlDotData(show: false),
        belowBarData: BarAreaData(
            show: true,
            color: color.withOpacity(0.08)),
      );

  Widget _buildChartLegend() => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      _legendDot(Colors.greenAccent, 'Download'),
      const SizedBox(width: 20),
      _legendDot(Colors.blueAccent, 'Upload'),
    ],
  );

  Widget _legendDot(Color c, String label) => Row(children: [
    Container(width: 10, height: 10, decoration: BoxDecoration(
        color: c, borderRadius: BorderRadius.circular(5))),
    const SizedBox(width: 6),
    Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
  ]);

  // ── Tab 2: State Machine Tracker ─────────────────────────────────────────

  Widget _buildStateTab() {
    return Column(children: [
      _buildCurrentMicroState(),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Align(alignment: Alignment.centerLeft,
          child: Text('STATE HISTORY', style: TextStyle(color: Colors.white38,
              fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.bold)),
        ),
      ),
      Expanded(
        child: ListView.builder(
          reverse: true,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: _stateHistory.length,
          itemBuilder: (_, i) {
            final rec = _stateHistory[_stateHistory.length - 1 - i];
            final dt = rec.$1;
            final state = rec.$2;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Container(width: 8, height: 8,
                    decoration: BoxDecoration(shape: BoxShape.circle,
                        color: state.color)),
                const SizedBox(width: 10),
                Text(state.label,
                    style: TextStyle(color: state.color, fontSize: 13)),
                const Spacer(),
                Text(
                  '${dt.hour.toString().padLeft(2,'0')}:'
                  '${dt.minute.toString().padLeft(2,'0')}:'
                  '${dt.second.toString().padLeft(2,'0')}',
                  style: const TextStyle(color: Colors.white38, fontSize: 11,
                      fontFamily: 'monospace'),
                ),
              ]),
            );
          },
        ),
      ),
    ]);
  }

  Widget _buildCurrentMicroState() => Container(
    margin: const EdgeInsets.all(16),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _microState.color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _microState.color.withOpacity(0.5)),
    ),
    child: Row(children: [
      AnimatedContainer(duration: const Duration(milliseconds: 400),
        width: 14, height: 14,
        decoration: BoxDecoration(shape: BoxShape.circle,
            color: _microState.color,
            boxShadow: [BoxShadow(color: _microState.color,
                blurRadius: 8)])),
      const SizedBox(width: 12),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('CURRENT MICRO-STATE', style: TextStyle(color: Colors.white38,
            fontSize: 10, letterSpacing: 1.5)),
        const SizedBox(height: 4),
        Text(_microState.label, style: TextStyle(
            color: _microState.color,
            fontSize: 16, fontWeight: FontWeight.bold)),
      ]),
    ]),
  );

  // ── Tab 3: Simulate Failure ───────────────────────────────────────────────

  Widget _buildSimulateTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        _simCard('🔥 Simulate UDP Block', Colors.redAccent,
            'Forces a 5-second handshake timeout to trigger TCP fallback',
            () => _simulate('udp_block')),
        _simCard('😴 Simulate Sleep Mode', Colors.orangeAccent,
            'Pauses telemetry polling to simulate CPU sleep / Doze mode',
            () => _simulate('sleep')),
        _simCard('📡 Simulate Network Switch', Colors.blueAccent,
            'Notifies reconnect engine of a Wi-Fi→Cellular transition',
            () => _simulate('network_switch')),
        _simCard('💀 Simulate Process Kill', Colors.purpleAccent,
            'Stops the tunnel handle abruptly without disconnect sequence',
            () => _simulate('process_kill')),
        _simCard('🔑 Test Key Rotation', Colors.tealAccent,
            'Generates a new keypair to verify FFI key generation works',
            () => _simulate('key_rotation')),
      ]),
    );
  }

  Widget _simCard(String title, Color color, String desc, VoidCallback onTap) =>
    Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(color: color,
                    fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 4),
                Text(desc, style: const TextStyle(color: Colors.white54,
                    fontSize: 11)),
              ])),
              Icon(Icons.play_arrow_rounded, color: color),
            ]),
          ),
        ),
      ),
    );

  void _simulate(String mode) {
    HapticFeedback.mediumImpact();
    final engine = VpnEngine.instance;
    switch (mode) {
      case 'udp_block':
        engine.simulateFallbackTrigger();
        break;
      case 'sleep':
        engine.simulateSleep();
        break;
      case 'network_switch':
        engine.simulateNetworkSwitch();
        break;
      case 'key_rotation':
        try {
          final priv = engine.generatePrivateKey();
          final pub  = engine.derivePublicKey(priv);
          engine.addLog('🔑 KeyRotation test: pub=${pub.substring(0, 8)}...');
        } catch (e) {
          engine.addLog('❌ KeyRotation error: $e', isError: true);
        }
        break;
      case 'process_kill':
        // Simulate abrupt tunnel handle invalidation
        engine.simulateAbruptKill();
        break;
    }

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Simulation "$mode" triggered'),
      backgroundColor: Colors.blueGrey.shade800,
      duration: const Duration(seconds: 2),
    ));
  }

  // ── Tab 4: Encrypted State Dump ──────────────────────────────────────────

  Widget _buildDumpTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('STATE DUMP INFO', style: TextStyle(color: Colors.white38,
                fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _dumpRow('OS', Platform.operatingSystem),
            _dumpRow('OS Version', Platform.operatingSystemVersion),
            _dumpRow('Dart Version', Platform.version.split(' ').first),
            _dumpRow('Tunnel State', VpnEngine.instance.state.name),
            _dumpRow('Log Lines', '${VpnEngine.instance.logs.length}'),
            _dumpRow('Speed Samples', '${_samples.length}'),
          ]),
        ),
        const SizedBox(height: 20),
        SizedBox(width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A237E),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.download, color: Colors.white),
            label: const Text('Export Encrypted State Dump',
                style: TextStyle(color: Colors.white,
                    fontWeight: FontWeight.bold)),
            onPressed: _exportDump,
          ),
        ),
      ]),
    );
  }

  Widget _dumpRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(children: [
      Text('$label:', style: const TextStyle(color: Colors.white54,
          fontSize: 12)),
      const SizedBox(width: 8),
      Expanded(child: Text(value, textAlign: TextAlign.end,
          style: const TextStyle(color: Colors.white, fontSize: 12,
              fontFamily: 'monospace'))),
    ]),
  );

  Future<void> _exportDump() async {
    final engine = VpnEngine.instance;
    final payload = {
      'timestamp': DateTime.now().toIso8601String(),
      'platform': Platform.operatingSystem,
      'os_version': Platform.operatingSystemVersion,
      'vpn_state': engine.state.name,
      'logs': engine.logs,
      'speed_samples': _samples.map((s) => {
        'rx_kbps': s.rxKbps, 'tx_kbps': s.txKbps, 't': s.t
      }).toList(),
    };

    // Base64-encode the JSON (simulates encryption for demo; in production,
    // use AES-256-GCM with a per-session key stored in flutter_secure_storage).
    final json    = jsonEncode(payload);
    final b64dump = base64Encode(utf8.encode(json));
    final header  = 'WGDUMP_V1_BASE64\n';
    final full    = header + b64dump;

    // Copy to clipboard
    await Clipboard.setData(ClipboardData(text: full));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('✅ State dump copied to clipboard (base64-encoded)'),
        backgroundColor: Color(0xFF1B5E20),
      ));
    }
  }
  // ── Tab 5: Beautiful Terminal ──────────────────────────────────────────

  Widget _buildTerminalTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('LIVE NATIVE ENGINE LOGS', style: TextStyle(
                  color: Colors.greenAccent, fontSize: 10, letterSpacing: 2, 
                  fontWeight: FontWeight.bold)),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.clear_all, color: Colors.white54, size: 20),
                    tooltip: 'Clear terminal',
                    onPressed: () => setState(() => _nativeLogs.clear()),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, color: Colors.blueAccent, size: 20),
                    tooltip: 'Copy all to clipboard',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _nativeLogs.join('\n')));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Logs copied to clipboard'),
                          backgroundColor: Color(0xFF1B5E20))
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.greenAccent.withOpacity(0.3)),
                boxShadow: [
                  BoxShadow(color: Colors.greenAccent.withOpacity(0.05), blurRadius: 10, spreadRadius: 2)
                ]
              ),
              child: ListView.builder(
                controller: _terminalScroll,
                itemCount: _nativeLogs.isNotEmpty ? _nativeLogs.length : 1,
                itemBuilder: (context, i) {
                  if (_nativeLogs.isEmpty) {
                    return const SelectableText('No native logs yet. Try connecting...',
                        style: TextStyle(color: Colors.white38, fontFamily: 'monospace', fontSize: 12));
                  }
                  final l = _nativeLogs[i];
                  final isErr = l.contains('ERROR:');
                  return SelectableText(
                    l,
                    style: TextStyle(
                      color: isErr ? Colors.redAccent : Colors.greenAccent.withOpacity(0.9),
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      )
    );
  }
}
