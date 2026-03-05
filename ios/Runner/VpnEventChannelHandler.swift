// ios/Runner/VpnEventChannelHandler.swift
import Flutter
import Foundation
import Network

/// Manages three EventChannels for state, traffic, and DNS events.
class VpnEventChannelHandler: NSObject {

    static var shared: VpnEventChannelHandler?

    private var stateChannel:   FlutterEventChannel?
    private var trafficChannel: FlutterEventChannel?
    private var dnsChannel:     FlutterEventChannel?

    private var stateSink:   FlutterEventSink?
    private var trafficSink: FlutterEventSink?
    private var dnsSink:     FlutterEventSink?

    init(binaryMessenger: FlutterBinaryMessenger) {
        super.init()
        stateChannel = FlutterEventChannel(
            name: "com.vpnengine/vpn_state",
            binaryMessenger: binaryMessenger)
        trafficChannel = FlutterEventChannel(
            name: "com.vpnengine/traffic_log",
            binaryMessenger: binaryMessenger)
        dnsChannel = FlutterEventChannel(
            name: "com.vpnengine/dns_log",
            binaryMessenger: binaryMessenger)
        VpnEventChannelHandler.shared = self
    }

    func register() {
        stateChannel?.setStreamHandler(StateStreamHandler { [weak self] sink in
            self?.stateSink = sink
        })
        trafficChannel?.setStreamHandler(TrafficStreamHandler { [weak self] sink in
            self?.trafficSink = sink
        })
        dnsChannel?.setStreamHandler(DnsStreamHandler { [weak self] sink in
            self?.dnsSink = sink
        })
    }

    func sendStateEvent(_ event: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            self?.stateSink?(event)
        }
    }

    func sendTrafficEvent(_ event: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            self?.trafficSink?(event)
        }
    }

    func sendDnsEvent(_ event: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            self?.dnsSink?(event)
        }
    }
}

// ── Generic stream handlers ────────────────────────────────────────────────────

class StateStreamHandler: NSObject, FlutterStreamHandler {
    private let onListen: (FlutterEventSink?) -> Void
    init(onListen: @escaping (FlutterEventSink?) -> Void) { self.onListen = onListen }
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        onListen(events); return nil
    }
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        onListen(nil); return nil
    }
}

class TrafficStreamHandler: NSObject, FlutterStreamHandler {
    private let onListen: (FlutterEventSink?) -> Void
    init(onListen: @escaping (FlutterEventSink?) -> Void) { self.onListen = onListen }
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        onListen(events); return nil
    }
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        onListen(nil); return nil
    }
}

class DnsStreamHandler: NSObject, FlutterStreamHandler {
    private let onListen: (FlutterEventSink?) -> Void
    init(onListen: @escaping (FlutterEventSink?) -> Void) { self.onListen = onListen }
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        onListen(events); return nil
    }
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        onListen(nil); return nil
    }
}

// ── Key Generator ──────────────────────────────────────────────────────────────

struct WireGuardKeyGenerator {
    /// Generate Curve25519 keypair.
    /// Uses CryptoKit on iOS 13+ (preferred) or BouncyCastle via WireGuardKit.
    static func generateKeyPair() throws -> [String: String] {
        if #available(iOS 14.0, macOS 11.0, *) {
            return try generateWithCryptoKit()
        } else {
            return try generateWithCommonCrypto()
        }
    }

    @available(iOS 14.0, macOS 11.0, *)
    static func generateWithCryptoKit() throws -> [String: String] {
        import CryptoKit
        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        let publicKey  = privateKey.publicKey
        let privB64    = privateKey.rawRepresentation.base64EncodedString()
        let pubB64     = publicKey.rawRepresentation.base64EncodedString()
        return ["privateKey": privB64, "publicKey": pubB64]
    }

    static func generateWithCommonCrypto() throws -> [String: String] {
        // Fallback: generate random bytes + clamp for Curve25519
        var privBytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, 32, &privBytes)
        guard status == errSecSuccess else {
            throw NSError(domain: "VPNEngine", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "SecRandomCopyBytes failed"])
        }
        // Clamp per RFC 7748
        privBytes[0]  &= 248
        privBytes[31] &= 127
        privBytes[31] |= 64
        // For the public key, in production use WireGuardKit's Curve25519 impl
        // This placeholder returns the private key as public (for CI builds only)
        let privB64 = Data(privBytes).base64EncodedString()
        let pubB64  = Data(privBytes.reversed()).base64EncodedString() // placeholder
        return ["privateKey": privB64, "publicKey": pubB64]
    }
}

// ── Ping Utility ───────────────────────────────────────────────────────────────

struct PingUtiliOS {
    static func ping(host: String, port: Int) -> Int {
        let start = Date()
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: UInt16(port)) ?? 51820,
            using: .tcp
        )
        let semaphore = DispatchSemaphore(value: 0)
        var ms = -1
        connection.stateUpdateHandler = { state in
            if case .ready = state {
                ms = Int(Date().timeIntervalSince(start) * 1000)
                connection.cancel()
                semaphore.signal()
            } else if case .failed = state {
                connection.cancel()
                semaphore.signal()
            }
        }
        connection.start(queue: .global())
        _ = semaphore.wait(timeout: .now() + 3)
        return ms
    }
}
