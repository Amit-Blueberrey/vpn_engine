// lib/ui/screens/home_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
// SAMPLE APP  –  VPN Engine Test UI
//
// HOW TO USE:
//   1. Tap the "Server Config" tab (gear icon at the bottom).
//   2. Fill in the five server-side fields you get from your WireGuard server:
//        • Server Endpoint   e.g.  vpn.example.com:51820
//        • Server Public Key e.g.  base64 key from [Peer] PublicKey
//        • Tunnel IP         e.g.  10.66.0.2/32
//        • DNS Servers       e.g.  1.1.1.1, 1.0.0.1
//        • Preshared Key     (optional)
//   3. Tap "Generate Keys" on the main screen to create a WireGuard key-pair.
//      The private key is stored encrypted on device.
//      Share the public key with your server admin for registration.
//   4. Once keys are generated and config is filled in, tap the big Connect
//      button.  The engine will:
//        a. Check / request VPN OS permission
//        b. Build a VpnConfig from your keys + server values
//        c. Call the native WireGuard layer via platform channel
//   5. Watch live traffic stats and DNS log update in real-time.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3.x: ChangeNotifierProvider is in legacy.dart
import 'package:flutter_riverpod/legacy.dart';
import '../../main.dart';
import '../../models/vpn_status.dart';
import '../../models/vpn_config.dart';
import '../widgets/connect_button.dart';
import '../widgets/status_card.dart';
import '../widgets/traffic_stats_card.dart';
import '../widgets/browsing_log_widget.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with TickerProviderStateMixin {
  int _selectedTab = 0;
  late final TabController _tabController;

  // ── Server-side config controllers (filled in by the user) ────────────────
  // These are the values that come from your WireGuard server / backend API.
  // In production you'd fetch these from a REST endpoint; here they're entered
  // manually for testing purposes.
  final _endpointCtrl = TextEditingController(text: 'vpn.example.com:51820');
  final _serverPubKeyCtrl = TextEditingController();
  final _tunnelIpCtrl = TextEditingController(text: '10.66.0.2/32');
  final _tunnelIpV6Ctrl = TextEditingController(text: 'fd42::2/128');
  final _dnsCtrl = TextEditingController(text: '1.1.1.1, 1.0.0.1');
  final _presharedKeyCtrl = TextEditingController();
  final _tunnelNameCtrl = TextEditingController(text: 'VPNEngine');
  final _mtuCtrl = TextEditingController(text: '1420');

  // ── State ─────────────────────────────────────────────────────────────────
  String? _publicKeyDisplay;
  bool _keysGenerated = false;
  bool _generatingKeys = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // Load saved public key on start
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final vpn = ref.read(vpnServiceProvider);
      final pk = await vpn.getSavedPublicKey();
      if (pk != null && mounted) {
        setState(() {
          _publicKeyDisplay = pk;
          _keysGenerated = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _endpointCtrl.dispose();
    _serverPubKeyCtrl.dispose();
    _tunnelIpCtrl.dispose();
    _tunnelIpV6Ctrl.dispose();
    _dnsCtrl.dispose();
    _presharedKeyCtrl.dispose();
    _tunnelNameCtrl.dispose();
    _mtuCtrl.dispose();
    super.dispose();
  }

  // ── Build VpnConfig from user-entered values + stored private key ─────────
  Future<VpnConfig?> _buildConfigFromInputs() async {
    final vpn = ref.read(vpnServiceProvider);
    final privateKey = await vpn.getSavedPrivateKey();

    if (privateKey == null) {
      _showSnack('⚠️ No private key found. Generate keys first.');
      return null;
    }

    final endpoint = _endpointCtrl.text.trim();
    final serverPubKey = _serverPubKeyCtrl.text.trim();
    final tunnelIp = _tunnelIpCtrl.text.trim();
    final dns = _dnsCtrl.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    if (endpoint.isEmpty || serverPubKey.isEmpty || tunnelIp.isEmpty) {
      _showSnack('⚠️ Fill in Endpoint, Server Public Key, and Tunnel IP.');
      return null;
    }

    final psk = _presharedKeyCtrl.text.trim();
    final tunnelIpV6 = _tunnelIpV6Ctrl.text.trim();
    final mtu = int.tryParse(_mtuCtrl.text.trim()) ?? 1420;

    return VpnConfig(
      tunnelName: _tunnelNameCtrl.text.trim().isEmpty
          ? 'VPNEngine'
          : _tunnelNameCtrl.text.trim(),
      privateKey: privateKey,
      address: tunnelIp,
      addressV6: tunnelIpV6.isEmpty ? null : tunnelIpV6,
      dnsServers: dns.isEmpty ? ['1.1.1.1', '1.0.0.1'] : dns,
      mtu: mtu,
      serverPublicKey: serverPubKey,
      presharedKey: psk.isEmpty ? null : psk,
      serverEndpoint: endpoint,
      allowedIPs: const ['0.0.0.0/0', '::/0'],
      persistentKeepalive: 25,
    );
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: const Color(0xFF1A1A2E),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final vpn = ref.watch(vpnServiceProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context, vpn),
            Expanded(
              child: IndexedStack(
                index: _selectedTab,
                children: [
                  _buildMainTab(vpn),
                  const BrowsingLogWidget(),
                  _buildConfigTab(),
                ],
              ),
            ),
            _buildBottomNav(),
          ],
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader(BuildContext context, dynamic vpn) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6C63FF), Color(0xFF3EC6E0)],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child:
                    const Icon(Icons.shield, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
              const Text(
                'VPN Engine',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.terminal, color: Colors.white54),
            onPressed: () => Navigator.pushNamed(context, '/logs'),
            tooltip: 'Debug Logs',
          ),
        ],
      ),
    );
  }

  // ── Main (Connect) Tab ────────────────────────────────────────────────────
  Widget _buildMainTab(dynamic vpn) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const SizedBox(height: 20),

          // Key status banner
          if (_keysGenerated)
            _InfoBanner(
              icon: Icons.check_circle,
              color: const Color(0xFF00C896),
              text: 'WireGuard keys ready',
            )
          else
            _InfoBanner(
              icon: Icons.warning_amber_rounded,
              color: const Color(0xFFFFAA00),
              text: 'Generate keys first  →  tap "Keys" button below',
            ),
          const SizedBox(height: 20),

          // Connect button
          ConnectButton(
            status: vpn.status,
            onConnect: () async {
              final config = await _buildConfigFromInputs();
              if (config == null) return;
              final result = await vpn.connect(config);
              if (!result.success && mounted) {
                _showSnack('❌ ${result.message}');
              }
            },
            onDisconnect: () => vpn.disconnect(),
          ),
          const SizedBox(height: 24),

          // Status card
          StatusCard(status: vpn.status),
          const SizedBox(height: 16),

          // Traffic stats
          TrafficStatsCard(stats: vpn.stats, isConnected: vpn.isConnected),
          const SizedBox(height: 16),

          // Quick actions
          _buildQuickActions(vpn),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildQuickActions(dynamic vpn) {
    return Row(
      children: [
        Expanded(
          child: _QuickActionButton(
            icon: Icons.key,
            label: _generatingKeys ? 'Generating…' : 'Gen Keys',
            isActive: _keysGenerated,
            onTap: _generatingKeys
                ? () {}
                : () async {
                    setState(() => _generatingKeys = true);
                    try {
                      final keys = await vpn.generateKeyPair();
                      setState(() {
                        _publicKeyDisplay = keys['publicKey'];
                        _keysGenerated = true;
                      });
                      if (mounted) _showKeysDialog(keys);
                    } finally {
                      if (mounted) setState(() => _generatingKeys = false);
                    }
                  },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _QuickActionButton(
            icon: Icons.refresh,
            label: 'Auto-Reconnect',
            isActive: vpn.autoReconnect,
            onTap: () => vpn.setAutoReconnect(!vpn.autoReconnect),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _QuickActionButton(
            icon: Icons.wifi_find,
            label: 'Ping Server',
            onTap: () async {
              final endpoint = _endpointCtrl.text.trim();
              if (endpoint.isEmpty) {
                _showSnack('Enter server endpoint in Config tab first.');
                return;
              }
              final parts = endpoint.split(':');
              final host = parts[0];
              final port =
                  parts.length > 1 ? int.tryParse(parts[1]) ?? 51820 : 51820;
              final ms = await vpn.ping(host, port);
              if (mounted) {
                _showSnack(ms >= 0 ? '✅ Ping: ${ms}ms' : '❌ Server unreachable');
              }
            },
          ),
        ),
      ],
    );
  }

  void _showKeysDialog(Map<String, String> keys) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('WireGuard Keypair',
            style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Your PUBLIC KEY (send this to your server admin):',
                style: TextStyle(color: Colors.white60, fontSize: 12)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF0D0D1A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF3EC6E0)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      keys['publicKey'] ?? '',
                      style: const TextStyle(
                          color: Color(0xFF3EC6E0), fontSize: 10),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy,
                        color: Colors.white38, size: 16),
                    onPressed: () {
                      Clipboard.setData(
                          ClipboardData(text: keys['publicKey'] ?? ''));
                      _showSnack('Public key copied!');
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF2A1A1A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
              ),
              child: Row(
                children: const [
                  Icon(Icons.lock, color: Colors.redAccent, size: 14),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'PRIVATE KEY stored securely on-device (Keychain/Keystore). '
                      'It is never shown or sent anywhere.',
                      style:
                          TextStyle(color: Colors.white54, fontSize: 10),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // ── Config Tab (Server Key/Value Input) ───────────────────────────────────
  // This is where the user pastes in the server-side values they received from
  // their WireGuard server or backend API.
  Widget _buildConfigTab() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // ── Section header ──────────────────────────────────────────────────
        const _SectionHeader(
          icon: Icons.dns,
          title: 'Server Configuration',
          subtitle:
              'Enter the values provided by your WireGuard server / admin.\n'
              'These are the [Peer] section values from the server side.',
        ),
        const SizedBox(height: 20),

        // ── Server endpoint ─────────────────────────────────────────────────
        _ConfigField(
          controller: _endpointCtrl,
          label: 'Server Endpoint',
          hint: 'vpn.example.com:51820  or  1.2.3.4:51820',
          icon: Icons.router,
          helperText: 'hostname or IP + WireGuard UDP port (default 51820)',
        ),
        const SizedBox(height: 14),

        // ── Server public key ───────────────────────────────────────────────
        _ConfigField(
          controller: _serverPubKeyCtrl,
          label: 'Server Public Key  *required*',
          hint: 'Base64 Curve25519 public key from the server [Interface]',
          icon: Icons.vpn_key,
          helperText:
              'Run `wg show` on the server and copy the "public key" value.\n'
              'Example: wIAi7gQ5p4j+u8Y8sMX6Ys1h...=',
          maxLines: 2,
        ),
        const SizedBox(height: 14),

        // ── Tunnel IP (assigned by server) ──────────────────────────────────
        _ConfigField(
          controller: _tunnelIpCtrl,
          label: 'Assigned Tunnel IPv4',
          hint: '10.66.0.2/32',
          icon: Icons.lan,
          helperText:
              'The IP your server assigned for this client (with /32 CIDR).',
        ),
        const SizedBox(height: 14),

        _ConfigField(
          controller: _tunnelIpV6Ctrl,
          label: 'Assigned Tunnel IPv6  (optional)',
          hint: 'fd42::2/128',
          icon: Icons.lan_outlined,
          helperText: 'Leave blank if your server does not use IPv6.',
        ),
        const SizedBox(height: 14),

        // ── DNS servers ─────────────────────────────────────────────────────
        _ConfigField(
          controller: _dnsCtrl,
          label: 'DNS Servers',
          hint: '1.1.1.1, 1.0.0.1',
          icon: Icons.search,
          helperText: 'Comma-separated. Use Cloudflare (1.1.1.1) or your '
              'server\'s private DNS.',
        ),
        const SizedBox(height: 14),

        // ── Preshared key (optional) ─────────────────────────────────────────
        _ConfigField(
          controller: _presharedKeyCtrl,
          label: 'Preshared Key  (optional)',
          hint: 'Base64 PSK for post-quantum hardening',
          icon: Icons.enhanced_encryption,
          helperText:
              'Only set this if your server\'s [Peer] entry has a PresharedKey.',
          obscureText: true,
        ),
        const SizedBox(height: 20),

        const Divider(color: Color(0xFF2A2A3E)),
        const SizedBox(height: 10),

        // ── Advanced section ────────────────────────────────────────────────
        const _SectionHeader(
          icon: Icons.tune,
          title: 'Advanced (optional)',
          subtitle: 'You usually don\'t need to change these.',
        ),
        const SizedBox(height: 16),

        Row(
          children: [
            Expanded(
              flex: 2,
              child: _ConfigField(
                controller: _tunnelNameCtrl,
                label: 'Tunnel Name',
                hint: 'VPNEngine',
                icon: Icons.label_outline,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ConfigField(
                controller: _mtuCtrl,
                label: 'MTU',
                hint: '1420',
                icon: Icons.tune,
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // ── Show current public key if generated ────────────────────────────
        if (_publicKeyDisplay != null) ...[
          const _SectionHeader(
            icon: Icons.key,
            title: 'Your Device Public Key',
            subtitle:
                'Send this to your server admin so they can add you as a peer.',
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0D1A1A),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF3EC6E0)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SelectableText(
                    _publicKeyDisplay!,
                    style: const TextStyle(
                        color: Color(0xFF3EC6E0),
                        fontSize: 10,
                        fontFamily: 'monospace'),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy,
                      color: Colors.white38, size: 16),
                  onPressed: () {
                    Clipboard.setData(
                        ClipboardData(text: _publicKeyDisplay!));
                    _showSnack('Public key copied!');
                  },
                ),
              ],
            ),
          ),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A0D),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: const Color(0xFFFFAA00).withOpacity(0.5)),
            ),
            child: Row(
              children: const [
                Icon(Icons.info_outline,
                    color: Color(0xFFFFAA00), size: 18),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'No keys found. Go to the main screen and tap "Gen Keys" '
                    'to generate your WireGuard key pair.',
                    style:
                        TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 30),

        // ── Quick reference ─────────────────────────────────────────────────
        _QuickRefCard(),
      ],
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A2E),
        border: Border(top: BorderSide(color: Color(0xFF2A2A3E))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _NavItem(
              icon: Icons.home,
              label: 'VPN',
              index: 0,
              selected: _selectedTab == 0,
              onTap: () => setState(() => _selectedTab = 0)),
          _NavItem(
              icon: Icons.list_alt,
              label: 'Log',
              index: 1,
              selected: _selectedTab == 1,
              onTap: () => setState(() => _selectedTab = 1)),
          _NavItem(
              icon: Icons.settings,
              label: 'Config',
              index: 2,
              selected: _selectedTab == 2,
              onTap: () => setState(() => _selectedTab = 2)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable Widgets
// ─────────────────────────────────────────────────────────────────────────────

class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _InfoBanner(
      {required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text,
                  style: TextStyle(color: color, fontSize: 12))),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _SectionHeader(
      {required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF6C63FF).withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: const Color(0xFF6C63FF), size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: const TextStyle(
                      color: Colors.white38, fontSize: 11)),
            ],
          ),
        ),
      ],
    );
  }
}

class _ConfigField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final String? helperText;
  final bool obscureText;
  final int maxLines;
  final TextInputType? keyboardType;

  const _ConfigField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.helperText,
    this.obscureText = false,
    this.maxLines = 1,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      maxLines: maxLines,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white24, fontSize: 11),
        helperText: helperText,
        helperStyle:
            const TextStyle(color: Colors.white30, fontSize: 10),
        helperMaxLines: 3,
        prefixIcon: Icon(icon, color: const Color(0xFF6C63FF), size: 18),
        filled: true,
        fillColor: const Color(0xFF1A1A2E),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF2A2A3E)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF2A2A3E)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF6C63FF)),
        ),
      ),
    );
  }
}

// Quick reference card explaining how to get server values
class _QuickRefCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D2A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF3A3A5E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Row(
            children: [
              Icon(Icons.help_outline,
                  color: Color(0xFF6C63FF), size: 16),
              SizedBox(width: 8),
              Text('How to get server values',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13)),
            ],
          ),
          SizedBox(height: 10),
          _RefLine(
              step: '1',
              text:
                  'On the WireGuard SERVER, run:  wg show wg0\n'
                  'Copy the "public key" → paste into "Server Public Key".'),
          _RefLine(
              step: '2',
              text:
                  'Server endpoint is your server\'s IP/hostname + port.\n'
                  'Default WireGuard port is 51820/UDP.'),
          _RefLine(
              step: '3',
              text:
                  'Server admin assigns your Tunnel IP (e.g. 10.66.0.2/32).\n'
                  'They add your device public key as a [Peer] on the server.'),
          _RefLine(
              step: '4',
              text:
                  'DNS: use 1.1.1.1 (Cloudflare), 8.8.8.8 (Google), or your\n'
                  'server\'s private DNS if it runs one.'),
        ],
      ),
    );
  }
}

class _RefLine extends StatelessWidget {
  final String step;
  final String text;
  const _RefLine({required this.step, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF6C63FF).withOpacity(0.3),
              shape: BoxShape.circle,
            ),
            child: Text(step,
                style: const TextStyle(
                    color: Color(0xFF6C63FF),
                    fontSize: 10,
                    fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    color: Colors.white54, fontSize: 11, height: 1.5)),
          ),
        ],
      ),
    );
  }
}

// ── Nav + action buttons ──────────────────────────────────────────────────────

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int index;
  final bool selected;
  final VoidCallback onTap;
  const _NavItem({
    required this.icon,
    required this.label,
    required this.index,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color =
        selected ? const Color(0xFF6C63FF) : Colors.white38;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: color, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isActive;
  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFF6C63FF).withOpacity(0.2)
              : const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive
                ? const Color(0xFF6C63FF)
                : const Color(0xFF2A2A3E),
          ),
        ),
        child: Column(
          children: [
            Icon(icon,
                color: isActive
                    ? const Color(0xFF6C63FF)
                    : Colors.white54,
                size: 20),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                  color: isActive
                      ? const Color(0xFF6C63FF)
                      : Colors.white54,
                  fontSize: 10,
                )),
          ],
        ),
      ),
    );
  }
}
