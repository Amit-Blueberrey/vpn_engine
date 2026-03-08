import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wireguard_flutter/wireguard_flutter.dart';
import 'engine/vpn_engine.dart';
import 'engine/vpn_config_builder.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => VpnEngine()..initialize()),
      ],
      child: const VpnApp(),
    ),
  );
}

class VpnApp extends StatelessWidget {
  const VpnApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WireGuard VPN Engine',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        primaryColor: Colors.blueAccent,
        scaffoldBackgroundColor: const Color(0xFF1E1E2C),
      ),
      home: const DashboardPage(),
    );
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({Key? key}) : super(key: key);

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  // Test config values - Replace with actual secure keys
  // For demo, we leave these with dummy validish base64 strings so it builds the config
  final String _privateKey = 'yAn...'; 
  final String _publicKey = 'pBl...';
  final String _address = '10.66.66.2/32';
  final String _endpoint = '198.51.100.1:51820'; 
  final String _allowedIPs = '0.0.0.0/0, ::/0';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('VPN Engine (WireGuard)'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Center(
        child: Consumer<VpnEngine>(
          builder: (context, engine, child) {
            final status = engine.vpnStage;
            final isConnected = status == VpnStage.connected;
            final isConnecting = status == VpnStage.connecting || status == VpnStage.preparing;

            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isConnected ? Colors.green.withOpacity(0.2) : Colors.grey.withOpacity(0.1),
                    border: Border.all(
                      color: isConnected ? Colors.greenAccent : Colors.grey,
                      width: 2,
                    )
                  ),
                  child: Icon(
                    isConnected ? Icons.security : Icons.shield_outlined,
                    size: 100,
                    color: isConnected ? Colors.greenAccent : Colors.grey,
                  ),
                ),
                const SizedBox(height: 30),
                Text(
                  'STATUS: ${status.name.toUpperCase()}',
                  style: TextStyle(
                    fontSize: 20, 
                    fontWeight: FontWeight.bold,
                    color: isConnected ? Colors.greenAccent : Colors.white,
                    letterSpacing: 2.0,
                  ),
                ),
                const SizedBox(height: 50),
                if (isConnecting)
                  const CircularProgressIndicator(color: Colors.blueAccent)
                else
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                      backgroundColor: isConnected ? Colors.redAccent : Colors.blueAccent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      elevation: 8,
                      shadowColor: isConnected ? Colors.redAccent.withOpacity(0.5) : Colors.blueAccent.withOpacity(0.5)
                    ),
                    onPressed: () {
                      if (isConnected) {
                        engine.disconnect();
                      } else {
                        final config = VpnConfigBuilder.buildString(
                          privateKey: _privateKey,
                          address: _address,
                          publicKey: _publicKey,
                          endpoint: _endpoint,
                          allowedIPs: _allowedIPs,
                          dns: '1.1.1.1',
                        );
                        engine.connect(config);
                      }
                    },
                    child: Text(
                      isConnected ? 'DISCONNECT' : 'CONNECT TO SERVER',
                      style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
