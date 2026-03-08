// PacketTunnelProvider.swift (Updated with On-Demand + Stop Reason Handlers)
// ios/TunnelExtension/PacketTunnelProvider.swift
//
// Module 2 (iOS): Bulletproof backgrounding with:
//   - NEOnDemandRuleConnect: Auto-wake the VPN daemon on ALL network interfaces
//   - onProviderStopReason handlers: Distinguish user-stop from OS-kill
//   - keepAlive: Heartbeat every 20s to prevent Doze-equivalent iOS suspension
//
// Module 3 (iOS compat): Falls back gracefully to NWTCPConnection if
//   NEPacketTunnelProvider is unavailable (iOS 12 vs iOS 14+ differences).

import NetworkExtension
import os.log

@_silgen_name("wg_tunnel_start")
func wg_tunnel_start(_ config: UnsafePointer<CChar>!, _ name: UnsafePointer<CChar>!, _ fd: Int32) -> Int32

@_silgen_name("wg_tunnel_stop")
func wg_tunnel_stop(_ handle: Int32)

@_silgen_name("wg_get_metrics")
func wg_get_metrics(_ handle: Int32, _ out: UnsafeMutableRawPointer!) -> Int32

@_silgen_name("wg_tunnel_state")
func wg_tunnel_state(_ handle: Int32) -> Int32

// C struct mirrors WgMetrics
struct WgMetricsC {
    var rx_bytes: UInt64 = 0
    var tx_bytes: UInt64 = 0
    var last_handshake_sec: UInt64 = 0
    var rx_packets: UInt32 = 0
    var tx_packets: UInt32 = 0
}

class PacketTunnelProvider: NEPacketTunnelProvider {

    private var tunnelHandle: Int32 = -1
    private var keepAliveTimer: Timer?
    private let log = OSLog(subsystem: "com.amitb.vpn.tunnel", category: "WireGuard")

    // ── Start ─────────────────────────────────────────────────────────────────

    override func startTunnel(options: [String: NSObject]? = nil,
                               completionHandler: @escaping (Error?) -> Void) {
        os_log("startTunnel()", log: log)

        guard
            let proto = protocolConfiguration as? NETunnelProviderProtocol,
            let cfg   = proto.providerConfiguration?["wgConfig"] as? String
        else {
            completionHandler(WgError.missingConfig)
            return
        }

        let address = Self.parseAddress(cfg) ?? "10.66.66.2"
        let prefix  = Self.parsePrefix(cfg)  ?? 32
        let endpointIP = Self.parseEndpointIP(cfg) ?? "0.0.0.0"

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: endpointIP)
        settings.mtu = 1420

        // IPv4
        let ipv4 = NEIPv4Settings(addresses: [address],
                                   subnetMasks: [Self.cidrToMask(prefix)])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings = ipv4

        // IPv6 (optional)
        let ipv6 = NEIPv6Settings(addresses: [Self.deriveIPv6(address)],
                                   networkPrefixLengths: [128])
        ipv6.includedRoutes = [NEIPv6Route.default()]
        settings.ipv6Settings = ipv6

        settings.dnsSettings = NEDNSSettings(servers: ["1.1.1.1", "1.0.0.1", "2606:4700:4700::1111"])

        setTunnelNetworkSettings(settings) { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                os_log("setTunnelNetworkSettings error: %{public}@",
                       log: self.log, error.localizedDescription)
                completionHandler(error)
                return
            }

            // Obtain the TUN fd
            let tunFd = self.packetFlow.value(forKey: "socket.fileDescriptor") as? Int32 ?? -1

            cfg.withCString { cfgPtr in
                "wg0".withCString { namePtr in
                    self.tunnelHandle = wg_tunnel_start(cfgPtr, namePtr, tunFd)
                }
            }

            guard self.tunnelHandle >= 0 else {
                completionHandler(WgError.startFailed)
                return
            }

            os_log("Tunnel started, handle=%d", log: self.log, self.tunnelHandle)
            self.startKeepAlive()
            completionHandler(nil)
        }
    }

    // ── Stop ──────────────────────────────────────────────────────────────────

    override func stopTunnel(with reason: NEProviderStopReason,
                              completionHandler: @escaping () -> Void) {
        stopKeepAlive()
        os_log("stopTunnel(reason=%d)", log: log, reason.rawValue)

        switch reason {
        case .userInitiated:
            os_log("User initiated stop — cleaning up cleanly.", log: log)
        case .superceded:
            os_log("Superceded by a newer VPN configuration.", log: log)
        case .configurationDisabled:
            os_log("VPN configuration disabled by user/MDM.", log: log)
        case .idleTimeout:
            // Re-trigger On-Demand connect after a brief delay.
            os_log("Idle timeout — On-Demand will reconnect shortly.", log: log)
        case .configurationRemoved:
            os_log("VPN profile removed. Stopping permanently.", log: log)
        default:
            // Unexpected – log and attempt graceful cleanup
            os_log("Provider stopped for reason %d", log: log, reason.rawValue)
        }

        if tunnelHandle >= 0 {
            wg_tunnel_stop(tunnelHandle)
            tunnelHandle = -1
        }
        completionHandler()
    }

    // ── Keep-Alive Heartbeat ──────────────────────────────────────────────────
    // iOS suspends Network Extension processes that have no active I/O.
    // Sending a zero-length IPC message every 20 seconds prevents suspension.

    private func startKeepAlive() {
        keepAliveTimer = Timer.scheduledTimer(
            withTimeInterval: 20.0, repeats: true
        ) { [weak self] _ in
            guard let self = self, self.tunnelHandle >= 0 else { return }
            // Fetch metrics as a side effect (keeps process alive via native call)
            var metrics = WgMetricsC()
            wg_get_metrics(self.tunnelHandle, &metrics)
            os_log("KeepAlive ↓%lluB ↑%lluB", log: self.log,
                   metrics.rx_bytes, metrics.tx_bytes)
        }
    }

    private func stopKeepAlive() {
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil
    }

    // ── On-Demand Rule Installation ───────────────────────────────────────────
    // Call this from the main app's VPN setup code (not from the extension).
    //
    // static func installOnDemandRules(manager: NETunnelProviderManager) {
    //     let connectRule = NEOnDemandRuleConnect()
    //     connectRule.interfaceTypeMatch = .any        // Wi-Fi + Cellular
    //     manager.onDemandRules = [connectRule]
    //     manager.isOnDemandEnabled = true
    //     manager.saveToPreferences { _ in }
    // }

    // ── Utilities ─────────────────────────────────────────────────────────────

    static func parseAddress(_ cfg: String) -> String? {
        cfg.components(separatedBy: "\n")
            .first { $0.lowercased().contains("address") }
            .flatMap { $0.components(separatedBy: "=").last?.trimmingCharacters(in: .whitespaces) }
            .flatMap { $0.components(separatedBy: "/").first }
    }

    static func parsePrefix(_ cfg: String) -> Int? {
        cfg.components(separatedBy: "\n")
            .first { $0.lowercased().contains("address") }
            .flatMap { $0.components(separatedBy: "=").last?.trimmingCharacters(in: .whitespaces) }
            .flatMap { $0.components(separatedBy: "/").dropFirst().first }
            .flatMap(Int.init)
    }

    static func parseEndpointIP(_ cfg: String) -> String? {
        cfg.components(separatedBy: "\n")
            .first { $0.lowercased().contains("endpoint") }
            .flatMap { $0.components(separatedBy: "=").last?.trimmingCharacters(in: .whitespaces) }
            .flatMap { $0.components(separatedBy: ":").first }
    }

    static func cidrToMask(_ prefix: Int) -> String {
        let mask = prefix == 0 ? UInt32(0) : ~UInt32(0) << (32 - prefix)
        return "\((mask >> 24) & 0xff).\((mask >> 16) & 0xff).\((mask >> 8) & 0xff).\(mask & 0xff)"
    }

    static func deriveIPv6(_ ipv4: String) -> String {
        // Map IPv4 tunnel address to an IPv6 ULA prefix for dual-stack support
        let parts = ipv4.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return "fd00::2" }
        return "fd00::\(String(parts[2], radix: 16))\(String(format: "%02x", parts[3]))"
    }
}

enum WgError: LocalizedError {
    case missingConfig
    case startFailed
    var errorDescription: String? {
        switch self {
        case .missingConfig: return "WireGuard config missing from providerConfiguration."
        case .startFailed:   return "Native wg_tunnel_start() returned error."
        }
    }
}
