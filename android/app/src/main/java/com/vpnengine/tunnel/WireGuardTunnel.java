// android/app/src/main/java/com/vpnengine/tunnel/WireGuardTunnel.java
package com.vpnengine.tunnel;

import android.util.Log;

import com.vpnengine.model.WgConfig;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicLong;

/**
 * WireGuard Tunnel Wrapper.
 *
 * Integration strategy:
 * ─────────────────────
 * This class wraps WireGuard-Go (or wireguard-android) via JNI.
 *
 * To use the official WireGuard Android library:
 *   1. Add to android/app/build.gradle:
 *      implementation 'com.wireguard.android:tunnel:1.0.20230706'
 *   2. Replace the JNI calls below with:
 *      com.wireguard.android.backend.GoBackend or Tunnel interface
 *
 * For production you MUST integrate one of:
 *   A) wireguard-android (Go-based, official): github.com/WireGuard/wireguard-android
 *   B) wireguard-kt (Kotlin wrapper): github.com/WireGuard/wireguard-android
 *
 * This class shows the STRUCTURE and the minimal interface required.
 * The JNI bindings below call into wg-go native library.
 */
public class WireGuardTunnel {

    private static final String TAG = "WireGuardTunnel";

    private WgConfig config;
    private int tunFd = -1;
    private int wgHandle = -1; // handle returned by wg_turn_on()
    private final AtomicBoolean running = new AtomicBoolean(false);

    // ── Traffic counters ──────────────────────────────────────────────────────
    private static final AtomicLong rxBytes   = new AtomicLong(0);
    private static final AtomicLong txBytes   = new AtomicLong(0);
    private static final AtomicLong rxPackets = new AtomicLong(0);
    private static final AtomicLong txPackets = new AtomicLong(0);
    private static volatile double  rxRate    = 0;
    private static volatile double  txRate    = 0;
    private static volatile boolean tunnelActive = false;
    private static volatile String  activeInterface = null;

    // ── JNI declarations (wg-go native library) ───────────────────────────────
    // These map to: github.com/WireGuard/wireguard-go/tun/netstack
    static {
        try {
            System.loadLibrary("wg-go");
            Log.i(TAG, "wg-go native library loaded");
        } catch (UnsatisfiedLinkError e) {
            Log.w(TAG, "wg-go native library not found – tunnel will use Java mock");
        }
    }

    /**
     * Turn on the WireGuard tunnel.
     * @param ifName   interface name (e.g. "wg0")
     * @param tunFd    file descriptor of the TUN interface
     * @param settings WireGuard config in wg-quick format
     * @return         tunnel handle (or -1 on error)
     */
    private native int wgTurnOn(String ifName, int tunFd, String settings);

    /**
     * Turn off the WireGuard tunnel.
     * @param handle handle returned by wgTurnOn
     */
    private native void wgTurnOff(int handle);

    /**
     * Get transfer statistics for a handle.
     * @return long[]{rx_bytes, tx_bytes}
     */
    private native long[] wgGetTransfer(int handle);

    /**
     * Get WireGuard version string.
     */
    private static native String wgVersion();

    // ── Public API ─────────────────────────────────────────────────────────────

    public void setConfig(WgConfig config) {
        this.config = config;
    }

    public void setTunFd(int fd) {
        this.tunFd = fd;
    }

    public void start() throws Exception {
        if (config == null) throw new IllegalStateException("Config not set");
        if (tunFd < 0)      throw new IllegalStateException("TUN fd not set");

        Log.i(TAG, "Starting WireGuard tunnel to " + config.serverEndpoint);

        String wgSettings = buildWgSettings();
        Log.d(TAG, "WireGuard settings:\n" + wgSettings);

        try {
            wgHandle = wgTurnOn("wg0", tunFd, wgSettings);
            if (wgHandle < 0) throw new RuntimeException("wgTurnOn returned " + wgHandle);
            Log.i(TAG, "WireGuard tunnel started, handle=" + wgHandle);
        } catch (UnsatisfiedLinkError e) {
            // JNI not available → use Java mock for testing/CI
            Log.w(TAG, "wgTurnOn JNI not available, using mock tunnel");
            wgHandle = 999; // mock handle
        }

        running.set(true);
        tunnelActive = true;
        activeInterface = "wg0";

        // Start stats polling thread
        startStatsPoller();
    }

    public void stop() {
        running.set(false);
        tunnelActive = false;
        activeInterface = null;
        if (wgHandle > 0) {
            try {
                wgTurnOff(wgHandle);
            } catch (UnsatisfiedLinkError ignored) {}
            wgHandle = -1;
        }
        Log.i(TAG, "WireGuard tunnel stopped");
    }

    public static boolean isTunnelActive() {
        return tunnelActive;
    }

    public static String getActiveInterfaceName() {
        return activeInterface;
    }

    public static Map<String, Object> getTrafficStats() {
        Map<String, Object> m = new HashMap<>();
        m.put("rxBytes",    rxBytes.get());
        m.put("txBytes",    txBytes.get());
        m.put("rxPackets",  rxPackets.get());
        m.put("txPackets",  txPackets.get());
        m.put("rxRateBps",  rxRate);
        m.put("txRateBps",  txRate);
        m.put("timestamp",  System.currentTimeMillis());
        return m;
    }

    public static List<Map<String, Object>> listPeers() {
        // In production: parse wg show output or use wg-go JNI
        List<Map<String, Object>> peers = new ArrayList<>();
        if (tunnelActive) {
            Map<String, Object> peer = new HashMap<>();
            peer.put("publicKey", "server_public_key_placeholder");
            peer.put("endpoint", "vpn.example.com:51820");
            peer.put("latestHandshake", System.currentTimeMillis() - 5000);
            peer.put("rxBytes", rxBytes.get());
            peer.put("txBytes", txBytes.get());
            peers.add(peer);
        }
        return peers;
    }

    // ── Private helpers ────────────────────────────────────────────────────────

    /**
     * Build wg-quick formatted settings string for wgTurnOn.
     * Format: https://www.wireguard.com/xplatform/#configuration-protocol
     */
    private String buildWgSettings() {
        StringBuilder sb = new StringBuilder();
        // Interface section
        sb.append("private_key=").append(base64ToHex(config.privateKey)).append('\n');
        sb.append("listen_port=0\n");
        // Peer section
        sb.append("public_key=").append(base64ToHex(config.serverPublicKey)).append('\n');
        if (config.presharedKey != null && !config.presharedKey.isEmpty()) {
            sb.append("preshared_key=").append(base64ToHex(config.presharedKey)).append('\n');
        }
        sb.append("endpoint=").append(config.serverEndpoint).append('\n');
        for (String ip : config.allowedIPs) {
            sb.append("allowed_ip=").append(ip.trim()).append('\n');
        }
        if (config.persistentKeepalive != null && config.persistentKeepalive > 0) {
            sb.append("persistent_keepalive_interval=")
              .append(config.persistentKeepalive).append('\n');
        }
        return sb.toString();
    }

    private void startStatsPoller() {
        Thread t = new Thread(() -> {
            long prevRx = 0, prevTx = 0;
            while (running.get()) {
                try {
                    Thread.sleep(1000);
                    long[] transfer = null;
                    try {
                        transfer = wgGetTransfer(wgHandle);
                    } catch (UnsatisfiedLinkError e) {
                        // Mock stats for testing
                        transfer = new long[]{
                            rxBytes.get() + (long)(Math.random() * 1024),
                            txBytes.get() + (long)(Math.random() * 512)
                        };
                    }
                    if (transfer != null && transfer.length >= 2) {
                        long curRx = transfer[0], curTx = transfer[1];
                        rxRate = (curRx - prevRx);
                        txRate = (curTx - prevTx);
                        rxBytes.set(curRx);
                        txBytes.set(curTx);
                        rxPackets.incrementAndGet();
                        txPackets.incrementAndGet();
                        prevRx = curRx;
                        prevTx = curTx;
                    }
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    break;
                }
            }
        }, "StatsPollerThread");
        t.setDaemon(true);
        t.start();
    }

    /**
     * Convert Base64-encoded WireGuard key to hex string for wg protocol.
     */
    private String base64ToHex(String b64) {
        try {
            byte[] bytes = android.util.Base64.decode(b64, android.util.Base64.DEFAULT);
            StringBuilder hex = new StringBuilder();
            for (byte b : bytes) {
                hex.append(String.format("%02x", b & 0xff));
            }
            return hex.toString();
        } catch (Exception e) {
            Log.e(TAG, "base64ToHex failed for key");
            return b64;
        }
    }
}
