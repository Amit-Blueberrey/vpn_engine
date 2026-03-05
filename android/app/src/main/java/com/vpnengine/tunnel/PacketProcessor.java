// android/app/src/main/java/com/vpnengine/tunnel/PacketProcessor.java
package com.vpnengine.tunnel;

import android.os.ParcelFileDescriptor;
import android.util.Log;

import com.vpnengine.utils.DnsInterceptor;

import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.net.InetAddress;
import java.nio.ByteBuffer;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * Reads IPv4/IPv6 packets from the TUN fd.
 * For each packet:
 *   - Parses IP/TCP/UDP headers
 *   - If DNS (UDP port 53): forwards to DnsInterceptor
 *   - Logs connection metadata (src, dst, protocol, bytes)
 *   - Notifies Flutter via callback
 *
 * NOTE: In production the actual packet forwarding to the WireGuard
 * socket is done by the wg-go library. This processor runs in parallel
 * to extract telemetry only.
 */
public class PacketProcessor implements Runnable {

    private static final String TAG = "PacketProcessor";
    private static final int BUFFER_SIZE = 65536;

    // IP protocol numbers
    private static final int PROTO_ICMP = 1;
    private static final int PROTO_TCP  = 6;
    private static final int PROTO_UDP  = 17;

    private final ParcelFileDescriptor tunFd;
    private final DnsInterceptor dnsInterceptor;
    private final TrafficCallback trafficCallback;
    private final AtomicBoolean running = new AtomicBoolean(false);

    public interface TrafficCallback {
        void onTrafficEntry(Map<String, Object> entry);
    }

    public PacketProcessor(ParcelFileDescriptor tunFd,
                           DnsInterceptor dnsInterceptor,
                           TrafficCallback trafficCallback) {
        this.tunFd          = tunFd;
        this.dnsInterceptor = dnsInterceptor;
        this.trafficCallback= trafficCallback;
    }

    @Override
    public void run() {
        running.set(true);
        Log.i(TAG, "PacketProcessor started");
        byte[] buffer = new byte[BUFFER_SIZE];
        ByteBuffer pkt = ByteBuffer.wrap(buffer);

        try (FileInputStream in = new FileInputStream(tunFd.getFileDescriptor())) {
            while (running.get()) {
                int len = in.read(buffer);
                if (len <= 0) continue;
                pkt.clear();
                pkt.limit(len);
                processPacket(pkt, len);
            }
        } catch (Exception e) {
            if (running.get()) {
                Log.e(TAG, "PacketProcessor read error", e);
            }
        }
        Log.i(TAG, "PacketProcessor stopped");
    }

    public void stop() {
        running.set(false);
    }

    // ── Packet parsing ─────────────────────────────────────────────────────────

    private void processPacket(ByteBuffer pkt, int len) {
        if (len < 20) return;
        int version = (pkt.get(0) >> 4) & 0xF;
        if (version == 4) {
            processIPv4(pkt, len);
        } else if (version == 6) {
            processIPv6(pkt, len);
        }
    }

    private void processIPv4(ByteBuffer pkt, int len) {
        try {
            int ihl = (pkt.get(0) & 0xF) * 4;
            int protocol = pkt.get(9) & 0xFF;

            byte[] srcBytes = new byte[4];
            byte[] dstBytes = new byte[4];
            pkt.position(12);
            pkt.get(srcBytes);
            pkt.get(dstBytes);

            String srcIp = InetAddress.getByAddress(srcBytes).getHostAddress();
            String dstIp = InetAddress.getByAddress(dstBytes).getHostAddress();

            pkt.position(ihl);

            switch (protocol) {
                case PROTO_TCP:
                    processTcpSegment(pkt, srcIp, dstIp, len, "TCP");
                    break;
                case PROTO_UDP:
                    processUdpSegment(pkt, srcIp, dstIp, len, "UDP");
                    break;
                case PROTO_ICMP:
                    notifyTraffic("ICMP", srcIp, 0, dstIp, 0, len, null, "out");
                    break;
            }
        } catch (Exception e) {
            Log.v(TAG, "Error parsing IPv4 packet: " + e.getMessage());
        }
    }

    private void processIPv6(ByteBuffer pkt, int len) {
        try {
            if (len < 40) return;
            int nextHeader = pkt.get(6) & 0xFF;
            byte[] srcBytes = new byte[16];
            byte[] dstBytes = new byte[16];
            pkt.position(8);
            pkt.get(srcBytes);
            pkt.get(dstBytes);
            String srcIp = InetAddress.getByAddress(srcBytes).getHostAddress();
            String dstIp = InetAddress.getByAddress(dstBytes).getHostAddress();
            pkt.position(40);
            if (nextHeader == PROTO_TCP) {
                processTcpSegment(pkt, srcIp, dstIp, len, "TCP6");
            } else if (nextHeader == PROTO_UDP) {
                processUdpSegment(pkt, srcIp, dstIp, len, "UDP6");
            }
        } catch (Exception e) {
            Log.v(TAG, "Error parsing IPv6 packet: " + e.getMessage());
        }
    }

    private void processTcpSegment(ByteBuffer pkt, String srcIp, String dstIp,
                                    int totalLen, String protocol) {
        if (pkt.remaining() < 4) return;
        int srcPort = ((pkt.get() & 0xFF) << 8) | (pkt.get() & 0xFF);
        int dstPort = ((pkt.get() & 0xFF) << 8) | (pkt.get() & 0xFF);
        notifyTraffic(protocol, srcIp, srcPort, dstIp, dstPort, totalLen, null, "out");
    }

    private void processUdpSegment(ByteBuffer pkt, String srcIp, String dstIp,
                                    int totalLen, String protocol) {
        if (pkt.remaining() < 4) return;
        int srcPort = ((pkt.get() & 0xFF) << 8) | (pkt.get() & 0xFF);
        int dstPort = ((pkt.get() & 0xFF) << 8) | (pkt.get() & 0xFF);

        // DNS: UDP port 53
        if (dstPort == 53 && pkt.remaining() > 4) {
            pkt.position(pkt.position() + 4); // skip length + checksum
            byte[] dnsPayload = new byte[pkt.remaining()];
            pkt.get(dnsPayload);
            dnsInterceptor.processQuery(dnsPayload, dstIp, (entry) -> {
                // DNS interceptor calls back with parsed DNS entry
            });
        }
        notifyTraffic(protocol, srcIp, srcPort, dstIp, dstPort, totalLen, null, "out");
    }

    private void notifyTraffic(String protocol, String srcIp, int srcPort,
                                String dstIp, int dstPort, int bytes,
                                String hostname, String direction) {
        Map<String, Object> entry = new HashMap<>();
        entry.put("timestamp", System.currentTimeMillis());
        entry.put("protocol",  protocol);
        entry.put("srcIp",     srcIp);
        entry.put("srcPort",   srcPort);
        entry.put("dstIp",     dstIp);
        entry.put("dstPort",   dstPort);
        entry.put("bytes",     (long) bytes);
        entry.put("hostname",  hostname);
        entry.put("direction", direction);
        trafficCallback.onTrafficEntry(entry);
    }
}
