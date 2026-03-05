// lib/ui/widgets/status_card.dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/vpn_status.dart';

class StatusCard extends StatefulWidget {
  final VpnStatus status;
  const StatusCard({super.key, required this.status});

  @override
  State<StatusCard> createState() => _StatusCardState();
}

class _StatusCardState extends State<StatusCard> {
  Timer? _uptimeTimer;
  Duration _uptime = Duration.zero;

  @override
  void initState() {
    super.initState();
    _startUptimeTimer();
  }

  @override
  void didUpdateWidget(StatusCard old) {
    super.didUpdateWidget(old);
    if (widget.status.isConnected && !old.status.isConnected) {
      _startUptimeTimer();
    } else if (!widget.status.isConnected) {
      _uptimeTimer?.cancel();
      _uptime = Duration.zero;
    }
  }

  void _startUptimeTimer() {
    _uptimeTimer?.cancel();
    _uptimeTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.status.isConnected) {
        setState(() {
          _uptime = widget.status.uptime ?? Duration.zero;
        });
      }
    });
  }

  @override
  void dispose() {
    _uptimeTimer?.cancel();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.status;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A2A3E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: s.isConnected
                      ? const Color(0xFF00C896)
                      : s.isConnecting
                          ? const Color(0xFFFFB300)
                          : Colors.white24,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                s.state.name.toUpperCase(),
                style: const TextStyle(
                    color: Colors.white60, fontSize: 11, letterSpacing: 1.5),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _Row(
            label: 'Tunnel IP',
            value: s.tunnelIp ?? '--',
          ),
          _Row(
            label: 'Server',
            value: s.serverEndpoint ?? '--',
          ),
          _Row(
            label: 'Interface',
            value: s.interfaceName ?? '--',
          ),
          _Row(
            label: 'Uptime',
            value: s.isConnected ? _formatDuration(_uptime) : '--',
          ),
          if (s.uplinkMs != null)
            _Row(label: 'Latency', value: '${s.uplinkMs}ms'),
          if (s.errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                s.errorMessage!,
                style: const TextStyle(color: Color(0xFFFF5252), fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white38, fontSize: 12)),
          Text(value,
              style:
                  const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }
}
