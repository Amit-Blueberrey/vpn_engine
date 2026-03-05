// lib/ui/widgets/traffic_stats_card.dart
import 'package:flutter/material.dart';
import '../../models/traffic_stats.dart';

class TrafficStatsCard extends StatelessWidget {
  final TrafficStats stats;
  final bool isConnected;
  const TrafficStatsCard({super.key, required this.stats, required this.isConnected});

  @override
  Widget build(BuildContext context) {
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
          const Text('Traffic',
              style: TextStyle(color: Colors.white60, fontSize: 11, letterSpacing: 1.5)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StatBlock(
                  icon: Icons.arrow_downward,
                  color: const Color(0xFF3EC6E0),
                  label: 'Downloaded',
                  value: stats.formattedRx,
                  rate: stats.formattedRxRate,
                  active: isConnected,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatBlock(
                  icon: Icons.arrow_upward,
                  color: const Color(0xFF6C63FF),
                  label: 'Uploaded',
                  value: stats.formattedTx,
                  rate: stats.formattedTxRate,
                  active: isConnected,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StatBlock(
                  icon: Icons.inbox,
                  color: const Color(0xFF3EC6E0),
                  label: 'RX Packets',
                  value: stats.rxPackets.toString(),
                  active: isConnected,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatBlock(
                  icon: Icons.outbox,
                  color: const Color(0xFF6C63FF),
                  label: 'TX Packets',
                  value: stats.txPackets.toString(),
                  active: isConnected,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatBlock extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String? rate;
  final bool active;

  const _StatBlock({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.rate,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    final displayColor = active ? color : Colors.white24;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: displayColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: displayColor.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: displayColor, size: 14),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(color: displayColor, fontSize: 10)),
            ],
          ),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  color: active ? Colors.white : Colors.white24,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
          if (rate != null)
            Text(rate!,
                style: TextStyle(color: displayColor, fontSize: 10)),
        ],
      ),
    );
  }
}
