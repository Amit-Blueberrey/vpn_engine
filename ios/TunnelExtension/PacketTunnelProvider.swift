// ios/TunnelExtension/PacketTunnelProvider.swift
// ─────────────────────────────────────────────────────────────────────────────
// This file is compiled as a SEPARATE app extension target (not the main app).
// Target: com.vpnengine.tunnel (Network Extension bundle)
//
// It uses WireGuardKit (official WireGuard Apple library) to run the tunnel.
// Add via SPM: https://github.com/WireGuard/wireguard-apple
// Package: WireGuardKit
// ─────────────────────────────────────────────────────────────────────────────

import NetworkExtension
import os.log

// import WireGuardKit  ← Uncomment after adding WireGuardKit via SPM

class PacketTunnelProvider: NEPacketTunnelProvider {

    private let log = OSLog(subsystem: "com.vpnengine.tunnel", category: "PacketTunnel")
    // private var adapter: WireGuardAdapter?  ← WireGuardKit
    private var statsTimer: Timer?
    private var rxBytes: Int64 = 0
    private var txBytes: Int64 = 0

    // ── Tunnel Start ───────────────────────────────────────────────────────────

    override func startTunnel(
        options: [String: NSObject]?,
        completionHandler: @escaping (Error?) -> Void
    ) {
        os_log("PacketTunnelProvider: startTunnel", log: log)

        // 1. Get WireGuard config string from options or providerConfiguration
        let configStr = options?["config"] as? String
            ?? (protocolConfiguration as? NETunnelProviderProtocol)?
               .providerConfiguration?["wgConfig"] as? String
            ?? ""

        if configStr.isEmpty {
            completionHandler(
                NSError(domain: "VPNEngine", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Empty WireGuard config"]))
            return
        }

        os_log("WireGuard config:\n%{public}@", log: log, configStr)

        // 2. Parse tunnel network settings from config
        guard let networkSettings = buildNetworkSettings(from: configStr) else {
            completionHandler(
                NSError(domain: "VPNEngine", code: -2,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to parse config"]))
            return
        }

        // 3. Apply network settings to OS
        setTunnelNetworkSettings(networkSettings) { [weak self] error in
            guard error == nil else {
                completionHandler(error)
                return
            }

            // 4. Start WireGuard adapter
            // In production with WireGuardKit:
            //
            // self?.adapter = WireGuardAdapter(with: self!) { logLevel, message in
            //     os_log("%{public}@", log: self!.log, message)
            // }
            // self?.adapter?.start(tunnelConfiguration: parsedConfig) { error in
            //     completionHandler(error)
            // }
            //
            // For now we start a mock that confirms connection
            self?.startMockTunnel()
            self?.startStatsTimer()
            completionHandler(nil)
        }
    }

    // ── Tunnel Stop ────────────────────────────────────────────────────────────

    override func stopTunnel(
        with reason: NEProviderStopReason,
        completionHandler: @escaping () -> Void
    ) {
        os_log("PacketTunnelProvider: stopTunnel reason=%d", log: log, reason.rawValue)
        statsTimer?.invalidate()
        statsTimer = nil
        // adapter?.stop { completionHandler() }  ← WireGuardKit
        completionHandler()
    }

    // ── IPC from main app ──────────────────────────────────────────────────────

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        guard let msg = String(data: messageData, encoding: .utf8) else {
            completionHandler?(nil); return
        }

        if msg == "getStats" {
            // adapter?.getRuntimeConfiguration { configStr in  ← WireGuardKit
            //     // parse rx/tx from configStr
            // }
            let stats: [String: Any] = [
                "rxBytes": rxBytes, "txBytes": txBytes,
                "rxPackets": 0, "txPackets": 0,
                "rxRateBps": 0.0, "txRateBps": 0.0,
                "timestamp": Int(Date().timeIntervalSince1970 * 1000)
            ]
            let data = try? JSONSerialization.data(withJSONObject: stats)
            completionHandler?(data)
        } else {
            completionHandler?(nil)
        }
    }

    // ── Private helpers ────────────────────────────────────────────────────────

    private func buildNetworkSettings(from configStr: String) -> NEPacketTunnelNetworkSettings? {
        // Parse wg-quick format
        var address: String = "10.0.0.2"
        var prefixLen: Int  = 32
        var dnsServers: [String] = ["1.1.1.1", "1.0.0.1"]
        var mtu: Int = 1420

        for line in configStr.components(separatedBy: "\n") {
            let parts = line.trimmingCharacters(in: .whitespaces)
                            .components(separatedBy: "=")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 2 else { continue }
            let key = parts[0].lowercased()
            let val = parts[1...].joined(separator: "=").trimmingCharacters(in: .whitespaces)

            switch key {
            case "address":
                let addrParts = val.components(separatedBy: ",")[0]
                    .trimmingCharacters(in: .whitespaces)
                    .components(separatedBy: "/")
                address   = addrParts[0]
                prefixLen = Int(addrParts.count > 1 ? addrParts[1] : "32") ?? 32
            case "dns":
                dnsServers = val.components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
            case "mtu":
                mtu = Int(val) ?? 1420
            default:
                break
            }
        }

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: address)

        // IPv4
        let ipv4 = NEIPv4Settings(
            addresses: [address],
            subnetMasks: [prefixLenToMask(prefixLen)]
        )
        ipv4.includedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings = ipv4

        // IPv6 (optional)
        let ipv6 = NEIPv6Settings(addresses: ["fd42::2"], networkPrefixLengths: [128])
        ipv6.includedRoutes = [NEIPv6Route.default()]
        settings.ipv6Settings = ipv6

        // DNS
        let dnsSettings = NEDNSSettings(servers: dnsServers)
        dnsSettings.matchDomains = [""] // match all domains
        settings.dnsSettings = dnsSettings

        settings.mtu = NSNumber(value: mtu)
        return settings
    }

    private func prefixLenToMask(_ prefix: Int) -> String {
        let mask: UInt32 = prefix == 0 ? 0 : (~UInt32(0) << (32 - prefix))
        return "\((mask >> 24) & 0xFF).\((mask >> 16) & 0xFF).\((mask >> 8) & 0xFF).\(mask & 0xFF)"
    }

    private func startMockTunnel() {
        // Mock packet reading loop (replace with WireGuardKit in production)
        DispatchQueue.global().async { [weak self] in
            while true {
                Thread.sleep(forTimeInterval: 0.1)
                guard let self = self else { break }
                // In production: read from self.packetFlow, send to WireGuard
                // self.packetFlow.readPackets { packets, protocols in ... }
                self.rxBytes += Int64.random(in: 100...2000)
                self.txBytes += Int64.random(in: 50...500)
            }
        }
    }

    private func startStatsTimer() {
        statsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            // Stats are retrieved on-demand via handleAppMessage
        }
    }
}
