import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../engine/vpn_engine.dart';
import '../../models/vpn_models.dart';
import '../../services/server_repository.dart';

class DashboardTab extends StatefulWidget {
  const DashboardTab({Key? key}) : super(key: key);

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulse;

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VpnEngine>(
      builder: (ctx, engine, _) {
        final state = engine.state;
        final connected = state == VpnState.connected;
        final connecting = state == VpnState.connecting || state == VpnState.disconnecting;

        return SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              children: [
                const SizedBox(height: 60),
                _buildStatusOrb(connected, connecting, state),
                const SizedBox(height: 40),
                _buildSpeedSection(engine),
                const SizedBox(height: 40),
                _buildSpeedChart(engine),
                const SizedBox(height: 50),
                _buildConnectButton(engine, connected, connecting),
                const SizedBox(height: 40),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusOrb(bool connected, bool connecting, VpnState state) {
    final color = _stateColor(state);
    return ScaleTransition(
      scale: connecting ? _pulse : const AlwaysStoppedAnimation(1.0),
      child: Container(
        width: 160, height: 160,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color.withOpacity(0.2), color.withOpacity(0.05), Colors.transparent],
          ),
          border: Border.all(color: color, width: 3),
          boxShadow: [BoxShadow(color: color.withOpacity(0.3), blurRadius: 40)],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(connected ? Icons.lock : Icons.lock_open, color: color, size: 50),
            const SizedBox(height: 12),
            Text(state.name.toUpperCase(),
                style: GoogleFonts.inter(
                    color: color, fontWeight: FontWeight.bold, letterSpacing: 2.0, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _buildSpeedSection(VpnEngine engine) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildSpeedCard('DOWNLOAD', engine.speedRx, Colors.greenAccent),
        _buildSpeedCard('UPLOAD', engine.speedTx, Colors.blueAccent),
      ],
    );
  }

  Widget _buildSpeedCard(String label, double bps, Color color) {
    String formatted = _formatBitrate(bps);
    return Column(
      children: [
        Text(label, style: GoogleFonts.inter(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        const SizedBox(height: 8),
        Text(formatted, style: GoogleFonts.outfit(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _buildSpeedChart(VpnEngine engine) {
    return Container(
      height: 80,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF151525),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: LineChart(
        LineChartData(
          minY: 0,
          gridData: FlGridData(show: false),
          titlesData: FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: engine.rxHistory.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value)).toList(),
              isCurved: true,
              color: Colors.greenAccent,
              barWidth: 2,
              isStrokeCapRound: true,
              dotData: FlDotData(show: false),
              belowBarData: BarAreaData(show: true, color: Colors.greenAccent.withOpacity(0.1)),
            ),
            LineChartBarData(
              spots: engine.txHistory.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value)).toList(),
              isCurved: true,
              color: Colors.blueAccent,
              barWidth: 2,
              isStrokeCapRound: true,
              dotData: FlDotData(show: false),
              belowBarData: BarAreaData(show: true, color: Colors.blueAccent.withOpacity(0.1)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectButton(VpnEngine engine, bool connected, bool connecting) {
    final state = engine.state;
    String label = 'PROTECT NETWORK';
    Color btnColor = const Color(0xFF1565C0);
    
    if (state == VpnState.connecting) {
      label = 'CONNECTING...';
      btnColor = Colors.orangeAccent;
    } else if (state == VpnState.disconnecting) {
      label = 'DISCONNECTING...';
      btnColor = Colors.orange;
    } else if (connected) {
      label = 'DISCONNECT';
      btnColor = const Color(0xFFB71C1C);
    } else if (state == VpnState.error) {
      label = 'RETRY CONNECTION';
      btnColor = Colors.redAccent;
    }

    return Container(
      width: double.infinity,
      height: 64,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: btnColor.withOpacity(0.3),
            blurRadius: 20, offset: const Offset(0, 8),
          )
        ],
      ),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: btnColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
          elevation: 0,
        ),
        onPressed: connecting ? null : () async {
          if (connected) {
            await engine.disconnect();
          } else {
            final repo = ServerRepository.instance;
            if (repo.servers.isNotEmpty) {
               await engine.connect(repo.servers.first.config);
            }
          }
        },
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (connecting) ...[
              const SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              ),
              const SizedBox(width: 12),
            ],
            Text(label, 
                style: GoogleFonts.inter(fontWeight: FontWeight.w800, letterSpacing: 1.5, fontSize: 16)),
          ],
        ),
      ),
    );
  }

  String _formatBitrate(double bps) {
    if (bps >= 1024 * 1024) return '${(bps / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    if (bps >= 1024) return '${(bps / 1024).toStringAsFixed(0)} KB/s';
    return '${bps.toInt()} B/s';
  }

  Color _stateColor(VpnState s) {
    switch (s) {
      case VpnState.connected: return Colors.greenAccent;
      case VpnState.connecting:
      case VpnState.disconnecting: return Colors.orangeAccent;
      case VpnState.error: return Colors.redAccent;
      default: return Colors.blueAccent;
    }
  }
}
