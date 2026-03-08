/// dashboard_screen.dart
///
/// Full-featured premium VPN dashboard UI.
/// Consumes VpnEngine via Provider.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../engine/vpn_engine.dart';
import '../engine/vpn_config_builder.dart';
import '../models/vpn_models.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {

  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulse;
  bool _showLogs = false;
  final _scrollCtrl = ScrollController();

  // ── Live Config from AWS EC2 Instance ──
  final _config = const VpnConfig(
    privateKey:    'iLrG/EQBjRup1+2SeCJvYtSsvav+TU/hAsWBNwy77n4=',
    address:       '10.0.0.2/32',
    serverPublicKey: 'cZ93r7NSXews2TScm8pPaBbGXb+knj6xIlldYEXaaAc=',
    endpoint:      '3.238.201.203:51820',
    allowedIPs:    '0.0.0.0/0',
    dns:           '1.1.1.1',
    tunnelName:    'wg0',
    autoFallback:  true, // Enable TCP WebSocket fallback testing
    relayUrl:      'wss://3.238.201.203:443',
    relayToken:    'secret-vantage-relay-2026',
  );

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _pulse = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VpnEngine>(
      builder: (ctx, engine, _) {
        final state     = engine.state;
        final metrics   = engine.metrics;
        final connected = state == VpnState.connected;
        final connecting = state == VpnState.connecting ||
            state == VpnState.disconnecting;

        return Scaffold(
          backgroundColor: const Color(0xFF0E0E1A),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: const Text('WireGuard Engine',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2)),
            centerTitle: true,
            actions: [
              IconButton(
                icon: Icon(_showLogs ? Icons.visibility_off : Icons.terminal,
                    color: Colors.white54),
                onPressed: () => setState(() => _showLogs = !_showLogs),
              )
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 20),
                _buildStatusOrb(connected, connecting, state),
                const SizedBox(height: 30),
                _buildMetrics(metrics, connected),
                const SizedBox(height: 30),
                _buildConnectButton(engine, connecting, connected),
                const SizedBox(height: 20),
                if (_showLogs) Expanded(child: _buildLogPanel(engine.logs))
                else _buildPlatformBadge(),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Status Orb ──────────────────────────────────────────────────────────────

  Widget _buildStatusOrb(bool connected, bool connecting, VpnState state) {
    final color = _stateColor(state);
    return ScaleTransition(
      scale: connecting ? _pulse : const AlwaysStoppedAnimation(1.0),
      child: Container(
        width: 180, height: 180,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color.withOpacity(0.3), color.withOpacity(0.05), Colors.transparent],
          ),
          border: Border.all(color: color, width: 2),
          boxShadow: [BoxShadow(color: color.withOpacity(0.4), blurRadius: 30)],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(connected ? Icons.lock : Icons.lock_open,
                color: color, size: 60),
            const SizedBox(height: 10),
            Text(state.name.toUpperCase(),
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2.0,
                    fontSize: 14)),
          ],
        ),
      ),
    );
  }

  // ── Metrics Cards ──────────────────────────────────────────────────────────

  Widget _buildMetrics(VpnMetrics m, bool connected) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Expanded(child: _metricCard('DOWNLOAD', Icons.south_rounded,
              m.rxFormatted, Colors.greenAccent, connected)),
          const SizedBox(width: 12),
          Expanded(child: _metricCard('UPLOAD', Icons.north_rounded,
              m.txFormatted, Colors.blueAccent, connected)),
        ],
      ),
    );
  }

  Widget _metricCard(String label, IconData icon, String value,
      Color color, bool active) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: active
            ? color.withOpacity(0.08)
            : Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: active ? color.withOpacity(0.5) : Colors.white12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  color: Colors.white54, fontSize: 11, letterSpacing: 1)),
        ]),
        const SizedBox(height: 8),
        Text(value,
            style: TextStyle(
                color: active ? Colors.white : Colors.white38,
                fontSize: 22,
                fontWeight: FontWeight.bold)),
      ]),
    );
  }

  // ── Connect Button ─────────────────────────────────────────────────────────

  Widget _buildConnectButton(
      VpnEngine engine, bool connecting, bool connected) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: double.infinity,
        height: 60,
        child: connecting
            ? const Center(
                child: CircularProgressIndicator(color: Colors.blueAccent))
            : ElevatedButton(
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30)),
                  backgroundColor:
                      connected ? const Color(0xFFB71C1C) : const Color(0xFF1565C0),
                  elevation: 12,
                  shadowColor: connected
                      ? Colors.red.withOpacity(0.5)
                      : Colors.blueAccent.withOpacity(0.5),
                ),
                onPressed: () async {
                  HapticFeedback.mediumImpact();
                  if (connected) {
                    await engine.disconnect();
                  } else {
                    await engine.connect(_config);
                  }
                },
                child: Text(
                  connected ? '  DISCONNECT  ' : '  CONNECT TO SERVER  ',
                  style: const TextStyle(
                      fontSize: 15,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5),
                ),
              ),
      ),
    );
  }

  // ── Log Panel ──────────────────────────────────────────────────────────────

  Widget _buildLogPanel(List<String> logs) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      }
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          child: Row(children: const [
            Icon(Icons.terminal, color: Colors.greenAccent, size: 14),
            SizedBox(width: 6),
            Text('ENGINE LOGS',
                style: TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2)),
          ]),
        ),
        Container(
          height: 200,
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.6),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.greenAccent.withOpacity(0.3)),
          ),
          child: ListView.builder(
            controller: _scrollCtrl,
            itemCount: logs.length,
            itemBuilder: (_, i) {
              final isErr = logs[i].contains('ERROR');
              return Text(
                logs[i],
                style: TextStyle(
                    color: isErr ? Colors.redAccent : Colors.greenAccent,
                    fontFamily: 'monospace',
                    fontSize: 10),
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Platform Badge ─────────────────────────────────────────────────────────

  Widget _buildPlatformBadge() {
    String platform;
    IconData icon;
    if (VpnEngine.instance.state == VpnState.disconnected) {
      platform = 'Native WireGuard Engine'; icon = Icons.shield;
    } else {
      platform = '🔐 All traffic encrypted'; icon = Icons.verified_user;
    }
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(icon, color: Colors.white30, size: 14),
      const SizedBox(width: 6),
      Text(platform,
          style: const TextStyle(color: Colors.white30, fontSize: 12)),
    ]);
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Color _stateColor(VpnState s) {
    switch (s) {
      case VpnState.connected:     return Colors.greenAccent;
      case VpnState.connecting:    return Colors.orangeAccent;
      case VpnState.disconnecting: return Colors.orange;
      case VpnState.error:         return Colors.redAccent;
      default:                     return Colors.blueGrey;
    }
  }
}
