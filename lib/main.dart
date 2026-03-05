// lib/main.dart
// ─────────────────────────────────────────────────────────────────────────────
// VPN Engine – app entry point
// Uses Riverpod 3.x.  ChangeNotifierProvider lives in legacy.dart in v3+.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3.x: ChangeNotifierProvider moved to legacy import
import 'package:flutter_riverpod/legacy.dart';
import 'services/vpn_engine_service.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/log_screen.dart';
import 'utils/vpn_logger.dart';

// ── Global provider (ChangeNotifierProvider via legacy import) ────────────────
final vpnServiceProvider = ChangeNotifierProvider<VpnEngineService>((ref) {
  final svc = VpnEngineService();
  svc.initialize();
  return svc;
});

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  VpnLogger.info('VPN Engine App starting...');
  runApp(
    const ProviderScope(
      child: VpnEngineApp(),
    ),
  );
}

class VpnEngineApp extends StatelessWidget {
  const VpnEngineApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VPN Engine',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C63FF),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0D0D1A),
        cardTheme:  CardThemeData(
          color: Color(0xFF1A1A2E),
          elevation: 0,
        ),
      ),
      routes: {
        '/': (context) => const HomeScreen(),
        '/logs': (context) => const LogScreen(),
      },
      initialRoute: '/',
    );
  }
}
