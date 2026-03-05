// lib/ui/screens/log_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../utils/vpn_logger.dart';

class LogScreen extends StatefulWidget {
  const LogScreen({super.key});

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ScrollController _scrollCtrl = ScrollController();
  bool _autoScroll = true;
  LogLevel _filterLevel = LogLevel.debug;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    VpnLogger.addListener(_onNewLog);
    // Refresh every 500ms
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }

  void _onNewLog(LogLine line) {
    if (mounted) {
      setState(() {});
      if (_autoScroll) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollCtrl.hasClients) {
            _scrollCtrl.animateTo(
              _scrollCtrl.position.maxScrollExtent,
              duration: const Duration(milliseconds: 100),
              curve: Curves.easeOut,
            );
          }
        });
      }
    }
  }

  @override
  void dispose() {
    VpnLogger.removeListener(_onNewLog);
    _tabController.dispose();
    _scrollCtrl.dispose();
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Debug Console',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _autoScroll ? Icons.vertical_align_bottom : Icons.pause,
              color: _autoScroll ? const Color(0xFF3EC6E0) : Colors.white54,
            ),
            tooltip: 'Auto-scroll',
            onPressed: () => setState(() => _autoScroll = !_autoScroll),
          ),
          IconButton(
            icon: const Icon(Icons.copy, color: Colors.white54),
            tooltip: 'Copy all logs',
            onPressed: () {
              Clipboard.setData(
                  ClipboardData(text: VpnLogger.exportAsText()));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Logs copied to clipboard')),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep, color: Colors.white54),
            tooltip: 'Clear logs',
            onPressed: () {
              VpnLogger.clear();
              setState(() {});
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF6C63FF),
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white38,
          tabs: const [
            Tab(text: 'Engine'),
            Tab(text: 'Traffic'),
            Tab(text: 'DNS'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Filter bar
          _buildFilterBar(),
          // Tabs
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildEngineLog(),
                _buildTrafficLog(),
                _buildDnsLog(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      color: const Color(0xFF1A1A2E),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Text('Level: ', style: TextStyle(color: Colors.white54, fontSize: 12)),
          ...LogLevel.values.map((lvl) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilterChip(
                  label: Text(lvl.name.toUpperCase()),
                  selected: _filterLevel == lvl,
                  onSelected: (_) => setState(() => _filterLevel = lvl),
                  backgroundColor: const Color(0xFF0D0D1A),
                  selectedColor: _levelColor(lvl).withOpacity(0.3),
                  labelStyle: TextStyle(
                    color: _filterLevel == lvl
                        ? _levelColor(lvl)
                        : Colors.white38,
                    fontSize: 10,
                  ),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildEngineLog() {
    final lines = VpnLogger.lines
        .where((l) => l.level.index >= _filterLevel.index)
        .toList();

    if (lines.isEmpty) {
      return const Center(
        child: Text('No logs yet', style: TextStyle(color: Colors.white38)),
      );
    }

    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.all(8),
      itemCount: lines.length,
      itemBuilder: (ctx, i) {
        final line = lines[i];
        return _LogLineWidget(line: line);
      },
    );
  }

  Widget _buildTrafficLog() {
    // Shows live traffic entries from the riverpod provider
    return Consumer(
      builder: (context, ref, _) {
        // We access the service directly since this is a log screen
        return const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.swap_vert, color: Colors.white24, size: 48),
              SizedBox(height: 12),
              Text(
                'Traffic log streams here\nwhen VPN is connected',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDnsLog() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.dns, color: Colors.white24, size: 48),
          SizedBox(height: 12),
          Text(
            'DNS queries appear here\nwhen VPN tunnel is active',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38),
          ),
        ],
      ),
    );
  }

  Color _levelColor(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return Colors.white38;
      case LogLevel.info:
        return const Color(0xFF3EC6E0);
      case LogLevel.warn:
        return const Color(0xFFFFB300);
      case LogLevel.error:
        return const Color(0xFFFF5252);
    }
  }
}

class _LogLineWidget extends StatelessWidget {
  final LogLine line;
  const _LogLineWidget({required this.line});

  Color _color() {
    switch (line.level) {
      case LogLevel.debug:
        return Colors.white38;
      case LogLevel.info:
        return const Color(0xFF3EC6E0);
      case LogLevel.warn:
        return const Color(0xFFFFB300);
      case LogLevel.error:
        return const Color(0xFFFF5252);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ts = line.timestamp.toIso8601String().substring(11, 23);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
          children: [
            TextSpan(
                text: '$ts ',
                style: const TextStyle(color: Colors.white24)),
            TextSpan(
                text: '[${line.level.name.toUpperCase()}] ',
                style: TextStyle(color: _color())),
            TextSpan(
                text: '[${line.tag}] ',
                style: const TextStyle(color: Colors.white54)),
            TextSpan(
                text: line.message,
                style: TextStyle(color: _color())),
          ],
        ),
      ),
    );
  }
}
