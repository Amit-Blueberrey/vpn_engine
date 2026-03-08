import 'package:flutter/foundation.dart';
import 'package:wireguard_flutter/wireguard_flutter.dart';

class VpnEngine extends ChangeNotifier {
  final WireGuardFlutter _wireguard = WireGuardFlutter.instance;

  VpnStage _vpnStage = VpnStage.disconnected;
  VpnStage get vpnStage => _vpnStage;

  String _tunnelName = 'my_vpn_tunnel';

  VpnEngine() {
    _wireguard.vpnStageSnapshot.listen((event) {
      _vpnStage = event;
      notifyListeners();
    });
  }

  Future<void> initialize({String tunnelName = 'my_vpn_tunnel'}) async {
    _tunnelName = tunnelName;
    try {
      await _wireguard.initialize(tunnelName: tunnelName);
    } catch (e) {
      debugPrint("Init error: $e");
    }
  }

  Future<void> connect(String config) async {
    try {
      if (_vpnStage == VpnStage.connected) return;
      
      await _wireguard.startVpn(
        serverAddress: '127.0.0.1', 
        wgQuickConfig: config,
        providerBundleIdentifier: 'com.amitb.vpn', 
      );
    } catch (e) {
      debugPrint("Failed to connect: $e");
    }
  }

  Future<void> disconnect() async {
    try {
      await _wireguard.stopVpn();
    } catch (e) {
      debugPrint("Failed to disconnect: $e");
    }
  }
}
