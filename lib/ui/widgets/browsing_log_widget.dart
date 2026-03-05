// lib/ui/widgets/browsing_log_widget.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../main.dart';
import '../../models/traffic_stats.dart';

class BrowsingLogWidget extends ConsumerStatefulWidget {
  const BrowsingLogWidget({super.key});

  @override
  ConsumerState<BrowsingLogWidget> createState() => _BrowsingLogWidgetState();
}

class _BrowsingLogWidgetState extends ConsumerState<BrowsingLogWidget>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vpn = ref.watch(vpnServiceProvider);

    return Column(
      children: [
        // ── Header ──────────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          color: const Color(0xFF1A1A2E),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Activity Log',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold)),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.refresh, color: Colors.white54, size: 18),
                        onPressed: vpn.refreshBrowsingLog,
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_sweep,
                            color: Colors.white54, size: 18),
                        onPressed: vpn.clearBrowsingLog,
                      ),
                    ],
                  ),
                ],
              ),
              // Search bar
              TextField(
                style: const TextStyle(color: Colors.white, fontSize: 12),
                decoration: InputDecoration(
                  hintText: 'Search hostname, IP...',
                  hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                  prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 16),
                  filled: true,
                  fillColor: const Color(0xFF0D0D1A),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: EdgeInsets.zero,
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
              ),
              const SizedBox(height: 8),
              TabBar(
                controller: _tab,
                indicatorColor: const Color(0xFF6C63FF),
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white38,
                labelStyle: const TextStyle(fontSize: 11),
                tabs: [
                  Tab(text: 'Browsing (${vpn.browsingLog.length})'),
                  Tab(text: 'DNS (${vpn.dnsLog.length})'),
                  Tab(text: 'Traffic (${vpn.trafficLog.length})'),
                ],
              ),
            ],
          ),
        ),
        // ── Tab Content ──────────────────────────────────────────────────────
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: [
              _buildBrowsingList(vpn.browsingLog),
              _buildDnsList(vpn.dnsLog),
              _buildTrafficList(vpn.trafficLog),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBrowsingList(List<BrowsingLogEntry> entries) {
    final filtered = _searchQuery.isEmpty
        ? entries
        : entries
            .where((e) =>
                e.hostname.toLowerCase().contains(_searchQuery) ||
                e.url.toLowerCase().contains(_searchQuery))
            .toList();

    if (filtered.isEmpty) return _emptyState('No browsing activity captured');

    return ListView.builder(
      itemCount: filtered.length,
      itemBuilder: (ctx, i) {
        final e = filtered[i];
        return _LogTile(
          leading: _protocolIcon(e.protocol),
          title: e.hostname,
          subtitle: e.url,
          trailing: TrafficStats.formatBytes(e.bytesTransferred),
          timestamp: e.timestamp,
          statusColor: e.statusCode != null && e.statusCode! >= 400
              ? const Color(0xFFFF5252)
              : const Color(0xFF00C896),
        );
      },
    );
  }

  Widget _buildDnsList(List<DnsLogEntry> entries) {
    final filtered = _searchQuery.isEmpty
        ? entries
        : entries
            .where((e) => e.hostname.toLowerCase().contains(_searchQuery))
            .toList();

    if (filtered.isEmpty) return _emptyState('No DNS queries captured');

    return ListView.builder(
      itemCount: filtered.length,
      itemBuilder: (ctx, i) {
        final e = filtered[i];
        return _LogTile(
          leading: Icon(
            e.blocked ? Icons.block : Icons.dns,
            size: 16,
            color: e.blocked ? const Color(0xFFFF5252) : const Color(0xFF3EC6E0),
          ),
          title: e.hostname,
          subtitle: e.answers.take(2).join(', '),
          trailing: '${e.responseMs}ms',
          timestamp: e.timestamp,
          statusColor: e.blocked ? const Color(0xFFFF5252) : const Color(0xFF3EC6E0),
        );
      },
    );
  }

  Widget _buildTrafficList(List<TrafficLogEntry> entries) {
    final filtered = _searchQuery.isEmpty
        ? entries
        : entries
            .where((e) =>
                (e.hostname ?? '').toLowerCase().contains(_searchQuery) ||
                e.dstIp.contains(_searchQuery))
            .toList();

    if (filtered.isEmpty) return _emptyState('No traffic captured');

    return ListView.builder(
      itemCount: filtered.length,
      itemBuilder: (ctx, i) {
        final e = filtered[i];
        return _LogTile(
          leading: Text(
            e.protocol,
            style: const TextStyle(
                color: Color(0xFF6C63FF), fontSize: 9, fontWeight: FontWeight.bold),
          ),
          title: e.hostname ?? e.dstIp,
          subtitle: '${e.srcIp}:${e.srcPort} → ${e.dstIp}:${e.dstPort}',
          trailing: TrafficStats.formatBytes(e.bytes),
          timestamp: e.timestamp,
          statusColor: e.direction == 'out'
              ? const Color(0xFF6C63FF)
              : const Color(0xFF3EC6E0),
        );
      },
    );
  }

  Widget _emptyState(String message) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.inbox, color: Colors.white24, size: 48),
            const SizedBox(height: 12),
            Text(message,
                style: const TextStyle(color: Colors.white38, fontSize: 13)),
            const SizedBox(height: 6),
            const Text(
              'Connect to VPN to start capturing',
              style: TextStyle(color: Colors.white24, fontSize: 11),
            ),
          ],
        ),
      );

  Widget _protocolIcon(String protocol) {
    final isHttps = protocol.toLowerCase() == 'https';
    return Icon(
      isHttps ? Icons.https : Icons.http,
      size: 16,
      color: isHttps ? const Color(0xFF00C896) : const Color(0xFFFFB300),
    );
  }
}

class _LogTile extends StatelessWidget {
  final Widget leading;
  final String title;
  final String subtitle;
  final String trailing;
  final DateTime timestamp;
  final Color statusColor;

  const _LogTile({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.timestamp,
    required this.statusColor,
  });

  @override
  Widget build(BuildContext context) {
    final ts = timestamp.toIso8601String().substring(11, 19);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF1A1A2E))),
      ),
      child: Row(
        children: [
          SizedBox(width: 28, child: Center(child: leading)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    overflow: TextOverflow.ellipsis),
                Text(subtitle,
                    style: const TextStyle(color: Colors.white38, fontSize: 10),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(trailing,
                  style: TextStyle(color: statusColor, fontSize: 10)),
              Text(ts,
                  style: const TextStyle(color: Colors.white24, fontSize: 9)),
            ],
          ),
        ],
      ),
    );
  }
}
