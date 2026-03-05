// ios/Runner/VpnManager.swift
import Foundation
import NetworkExtension

/// Singleton that manages the iOS/macOS NetworkExtension (NETunnelProviderManager)
/// for WireGuard packet tunnel.
///
/// Architecture:
///   App process → NETunnelProviderManager → PacketTunnelProvider (extension)
///   PacketTunnelProvider wraps WireGuardKit (WireGuard official Apple library)
///
/// Setup required (not code – Xcode/entitlements):
///   1. Add "Network Extensions" capability → "Packet Tunnel" checked
///   2. Add App Group (e.g. group.com.vpnengine) to both targets
///   3. TunnelExtension target: add WireGuardKit via SPM
///      https://github.com/WireGuard/wireguard-apple
///   4. Info.plist for extension: NSExtension → NSExtensionPrincipalClass → PacketTunnelProvider
class VpnManager {

    static let shared = VpnManager()

    private let tunnelBundleId = "com.vpnengine.tunnel"
    private let appGroup       = "group.com.vpnengine"
    private var manager: NETunnelProviderManager?
    private var connectionStartTime: Date?
    private var currentConfig: WgConfigiOS?
    private var browsingLog: [[String: Any]] = []
    private var dnsServers: [String] = ["1.1.1.1", "1.0.0.1"]

    private init() {
        setupVPNStatusObserver()
    }

    // ── Initialize ─────────────────────────────────────────────────────────────

    func initialize(completion: @escaping (Bool) -> Void) {
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
            if let error = error {
                NSLog("VpnManager: loadAllFromPreferences error: \(error)")
                completion(false)
                return
            }
            // Find existing or create new manager for our tunnel extension
            self?.manager = managers?.first(where: {
                ($0.protocolConfiguration as? NETunnelProviderProtocol)?
                    .providerBundleIdentifier == self?.tunnelBundleId
            }) ?? NETunnelProviderManager()

            NSLog("VpnManager: initialized, manager loaded")
            completion(true)
        }
    }

    // ── Connect ────────────────────────────────────────────────────────────────

    func connect(config: WgConfigiOS, completion: @escaping (Bool, String, String?) -> Void) {
        currentConfig = config
        saveToPreferences(config: config) { [weak self] error in
            if let error = error {
                NSLog("VpnManager: saveToPreferences error: \(error)")
                completion(false, "Failed to save VPN config: \(error.localizedDescription)", nil)
                return
            }
            do {
                try self?.manager?.connection.startVPNTunnel(options: [
                    "config": config.toWireGuardFormat() as NSObject
                ])
                self?.connectionStartTime = Date()
                NSLog("VpnManager: tunnel start requested")
                completion(true, "Connecting...", config.address.components(separatedBy: "/").first)
            } catch {
                NSLog("VpnManager: startVPNTunnel error: \(error)")
                completion(false, error.localizedDescription, nil)
            }
        }
    }

    // ── Disconnect ─────────────────────────────────────────────────────────────

    func disconnect(completion: @escaping () -> Void) {
        manager?.connection.stopVPNTunnel()
        connectionStartTime = nil
        completion()
    }

    // ── Status ─────────────────────────────────────────────────────────────────

    var isConnected: Bool {
        return manager?.connection.status == .connected
    }

    func getStatus() -> [String: Any] {
        let status = manager?.connection.status ?? .disconnected
        var map: [String: Any] = [:]
        switch status {
        case .connected:     map["state"] = "connected"
        case .connecting:    map["state"] = "connecting"
        case .disconnecting: map["state"] = "disconnecting"
        case .reasserting:   map["state"] = "reconnecting"
        default:             map["state"] = "disconnected"
        }
        map["tunnelIp"]       = currentConfig?.address ?? ""
        map["serverEndpoint"] = currentConfig?.serverEndpoint ?? ""
        map["interfaceName"]  = isConnected ? "utun0" : nil
        if let start = connectionStartTime, isConnected {
            map["connectedAt"] = Int(start.timeIntervalSince1970 * 1000)
        }
        return map
    }

    // ── Traffic Stats ──────────────────────────────────────────────────────────

    func getTrafficStats() -> [String: Any] {
        // Request stats from the tunnel extension via IPC
        var stats: [String: Any] = [
            "rxBytes": 0, "txBytes": 0, "rxPackets": 0, "txPackets": 0,
            "rxRateBps": 0.0, "txRateBps": 0.0,
            "timestamp": Int(Date().timeIntervalSince1970 * 1000)
        ]
        // Send message to PacketTunnelProvider
        if let session = manager?.connection as? NETunnelProviderSession {
            try? session.sendProviderMessage("getStats".data(using: .utf8)!) { response in
                if let data = response,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    stats = json
                }
            }
        }
        return stats
    }

    // ── Peers ──────────────────────────────────────────────────────────────────

    func listPeers() -> [[String: Any]] {
        guard isConnected, let config = currentConfig else { return [] }
        return [[
            "publicKey": config.serverPublicKey,
            "endpoint":  config.serverEndpoint,
            "latestHandshake": Int(Date().timeIntervalSince1970 * 1000),
        ]]
    }

    // ── Config management ──────────────────────────────────────────────────────

    func importConfig(config: WgConfigiOS, completion: @escaping (Bool) -> Void) {
        currentConfig = config
        saveToPreferences(config: config) { error in
            completion(error == nil)
        }
    }

    func removeConfig(tunnelName: String, completion: @escaping (Bool) -> Void) {
        manager?.removeFromPreferences { error in
            completion(error == nil)
        }
    }

    func requestPermission(completion: @escaping (Bool) -> Void) {
        // On iOS, the VPN permission dialog is shown when saving config
        if manager == nil { manager = NETunnelProviderManager() }
        saveToPreferences(config: currentConfig ?? WgConfigiOS.placeholder()) { error in
            completion(error == nil)
        }
    }

    func setDnsServers(_ servers: [String]) {
        dnsServers = servers
    }

    // ── Browsing log ──────────────────────────────────────────────────────────

    func getBrowsingLog() -> [[String: Any]] { browsingLog }
    func clearBrowsingLog() { browsingLog.removeAll() }

    func addBrowsingEntry(_ entry: [String: Any]) {
        browsingLog.insert(entry, at: 0)
        if browsingLog.count > 1000 { browsingLog.removeLast() }
    }

    // ── Private ────────────────────────────────────────────────────────────────

    private func saveToPreferences(config: WgConfigiOS, completion: @escaping (Error?) -> Void) {
        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = tunnelBundleId
        proto.serverAddress            = config.serverEndpoint
        // Pass config to extension via providerConfiguration
        proto.providerConfiguration    = ["wgConfig": config.toWireGuardFormat()]

        manager?.protocolConfiguration = proto
        manager?.localizedDescription  = "VPN Engine – \(config.tunnelName)"
        manager?.isEnabled             = true

        manager?.saveToPreferences { error in
            completion(error)
        }
    }

    private func setupVPNStatusObserver() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NEVPNStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let conn = notification.object as? NEVPNConnection else { return }
            self?.onVpnStatusChanged(conn.status)
        }
    }

    private func onVpnStatusChanged(_ status: NEVPNStatus) {
        let stateString: String
        switch status {
        case .connected:     stateString = "connected";     connectionStartTime = Date()
        case .connecting:    stateString = "connecting"
        case .disconnecting: stateString = "disconnecting"
        case .disconnected:  stateString = "disconnected";  connectionStartTime = nil
        case .reasserting:   stateString = "reconnecting"
        default:             stateString = "disconnected"
        }
        NSLog("VPN status changed: \(stateString)")
        VpnEventChannelHandler.shared?.sendStateEvent([
            "state":          stateString,
            "tunnelIp":       currentConfig?.address.components(separatedBy: "/").first ?? "",
            "serverEndpoint": currentConfig?.serverEndpoint ?? "",
            "interfaceName":  status == .connected ? "utun0" : "",
        ])
    }
}

// ── WgConfigiOS ───────────────────────────────────────────────────────────────

struct WgConfigiOS {
    let tunnelName: String
    let privateKey: String
    let address: String
    let addressV6: String?
    let dnsServers: [String]
    let mtu: Int
    let serverPublicKey: String
    let presharedKey: String?
    let serverEndpoint: String
    let allowedIPs: [String]
    let persistentKeepalive: Int?

    init(from map: [String: Any]) {
        tunnelName          = map["tunnelName"] as? String ?? "VPNEngine"
        privateKey          = map["privateKey"] as? String ?? ""
        address             = map["address"] as? String ?? ""
        addressV6           = map["addressV6"] as? String
        dnsServers          = map["dnsServers"] as? [String] ?? ["1.1.1.1"]
        mtu                 = map["mtu"] as? Int ?? 1420
        serverPublicKey     = map["serverPublicKey"] as? String ?? ""
        presharedKey        = map["presharedKey"] as? String
        serverEndpoint      = map["serverEndpoint"] as? String ?? ""
        allowedIPs          = map["allowedIPs"] as? [String] ?? ["0.0.0.0/0"]
        persistentKeepalive = map["persistentKeepalive"] as? Int
    }

    static func placeholder() -> WgConfigiOS {
        return WgConfigiOS(from: [
            "tunnelName": "VPNEngine", "privateKey": "", "address": "10.0.0.2/32",
            "serverPublicKey": "", "serverEndpoint": "vpn.example.com:51820",
            "allowedIPs": ["0.0.0.0/0"], "dnsServers": ["1.1.1.1"]
        ])
    }

    /// Convert to WireGuard wg-quick format string for the tunnel extension
    func toWireGuardFormat() -> String {
        var s = "[Interface]\n"
        s += "PrivateKey = \(privateKey)\n"
        s += "Address = \(address)"
        if let v6 = addressV6, !v6.isEmpty { s += ", \(v6)" }
        s += "\n"
        s += "DNS = \(dnsServers.joined(separator: ", "))\n"
        s += "MTU = \(mtu)\n\n"
        s += "[Peer]\n"
        s += "PublicKey = \(serverPublicKey)\n"
        if let psk = presharedKey, !psk.isEmpty { s += "PresharedKey = \(psk)\n" }
        s += "Endpoint = \(serverEndpoint)\n"
        s += "AllowedIPs = \(allowedIPs.joined(separator: ", "))\n"
        if let ka = persistentKeepalive { s += "PersistentKeepalive = \(ka)\n" }
        return s
    }
}
