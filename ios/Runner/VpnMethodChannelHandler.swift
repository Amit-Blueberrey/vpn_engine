// ios/Runner/VpnMethodChannelHandler.swift
import Flutter
import NetworkExtension
import Security

/// Handles all MethodChannel calls from Flutter.
/// Channel: com.vpnengine/wireguard
class VpnMethodChannelHandler: NSObject {

    static let channelName = "com.vpnengine/wireguard"

    private let channel: FlutterMethodChannel
    private let vpnManager = VpnManager.shared
    private var pendingPermissionResult: FlutterResult?

    init(binaryMessenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(
            name: VpnMethodChannelHandler.channelName,
            binaryMessenger: binaryMessenger
        )
        super.init()
    }

    func register() {
        channel.setMethodCallHandler(handle)
        NSLog("VPN method channel registered")
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        NSLog("MethodChannel: \(call.method)")
        switch call.method {
        case "initialize":          handleInitialize(result: result)
        case "connect":             handleConnect(call: call, result: result)
        case "disconnect":          handleDisconnect(result: result)
        case "getStatus":           handleGetStatus(result: result)
        case "getTrafficStats":     handleGetTrafficStats(result: result)
        case "generateKeyPair":     handleGenerateKeyPair(result: result)
        case "importConfig":        handleImportConfig(call: call, result: result)
        case "removeConfig":        handleRemoveConfig(call: call, result: result)
        case "isPermissionGranted": handleIsPermissionGranted(result: result)
        case "requestPermission":   handleRequestPermission(result: result)
        case "checkTunInterface":   result(vpnManager.isConnected)
        case "getActiveInterface":  result(vpnManager.isConnected ? "utun0" : nil)
        case "listPeers":           result(vpnManager.listPeers())
        case "getBrowsingLog":      result(vpnManager.getBrowsingLog())
        case "clearBrowsingLog":    vpnManager.clearBrowsingLog(); result(nil)
        case "setDnsServers":       handleSetDnsServers(call: call, result: result)
        case "pingServer":          handlePingServer(call: call, result: result)
        default:                    result(FlutterMethodNotImplemented)
        }
    }

    // ── Handlers ────────────────────────────────────────────────────────────────

    private func handleInitialize(result: @escaping FlutterResult) {
        vpnManager.initialize { success in
            result(success)
        }
    }

    private func handleConnect(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any] else {
            result(["success": false, "message": "Invalid arguments"])
            return
        }
        let config = WgConfigiOS(from: args)
        vpnManager.connect(config: config) { success, message, tunnelIp in
            result(["success": success, "message": message, "assignedTunnelIp": tunnelIp ?? ""])
        }
    }

    private func handleDisconnect(result: @escaping FlutterResult) {
        vpnManager.disconnect {
            result(true)
        }
    }

    private func handleGetStatus(result: @escaping FlutterResult) {
        result(vpnManager.getStatus())
    }

    private func handleGetTrafficStats(result: @escaping FlutterResult) {
        result(vpnManager.getTrafficStats())
    }

    private func handleGenerateKeyPair(result: @escaping FlutterResult) {
        do {
            let keys = try WireGuardKeyGenerator.generateKeyPair()
            result(keys)
        } catch {
            result(FlutterError(code: "KEY_GEN_ERROR",
                                message: error.localizedDescription,
                                details: nil))
        }
    }

    private func handleImportConfig(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any] else {
            result(false); return
        }
        let config = WgConfigiOS(from: args)
        vpnManager.importConfig(config: config) { success in
            result(success)
        }
    }

    private func handleRemoveConfig(call: FlutterMethodCall, result: @escaping FlutterResult) {
        let tunnelName = (call.arguments as? [String: Any])?["tunnelName"] as? String ?? ""
        vpnManager.removeConfig(tunnelName: tunnelName) { success in
            result(success)
        }
    }

    private func handleIsPermissionGranted(result: @escaping FlutterResult) {
        // On iOS, NEVPNManager doesn't require explicit permission beyond
        // the user approving the VPN configuration on first install.
        // We check by loading the manager.
        NEVPNManager.shared().loadFromPreferences { error in
            result(error == nil)
        }
    }

    private func handleRequestPermission(result: @escaping FlutterResult) {
        // Permission is implicitly requested when saving VPN config.
        // iOS will show a system dialog on first NEVPNManager.saveToPreferences()
        vpnManager.requestPermission { granted in
            result(granted)
        }
    }

    private func handleSetDnsServers(call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any]
        let servers = args?["dnsServers"] as? [String] ?? []
        vpnManager.setDnsServers(servers)
        result(true)
    }

    private func handlePingServer(call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any]
        let host = args?["host"] as? String ?? ""
        let port = args?["port"] as? Int ?? 51820
        DispatchQueue.global().async {
            let ms = PingUtiliOS.ping(host: host, port: port)
            DispatchQueue.main.async { result(ms) }
        }
    }
}
