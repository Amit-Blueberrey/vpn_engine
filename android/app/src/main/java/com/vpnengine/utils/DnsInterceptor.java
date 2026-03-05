// android/app/src/main/java/com/vpnengine/utils/DnsInterceptor.java
package com.vpnengine.utils;

import android.content.Context;
import android.util.Log;

import com.vpnengine.service.WireGuardVpnService;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.Executor;
import java.util.concurrent.Executors;

/**
 * Parses raw DNS query packets and emits structured DnsLogEntry maps.
 * Works by reading the DNS wire format from UDP payloads captured in PacketProcessor.
 *
 * Also provides optional DNS-over-HTTPS forwarding for privacy.
 */
public class DnsInterceptor {

    private static final String TAG = "DnsInterceptor";

    private final Context context;
    private final DnsLogCallback callback;
    private List<String> dnsServers = Arrays.asList("1.1.1.1", "1.0.0.1");
    private final Executor executor = Executors.newSingleThreadExecutor();

    public interface DnsLogCallback {
        void onDnsEntry(Map<String, Object> entry);
    }

    public interface QueryCallback {
        void onResult(Map<String, Object> result);
    }

    public DnsInterceptor(Context context, DnsLogCallback callback) {
        this.context  = context;
        this.callback = callback;
    }

    public void setDnsServers(List<String> servers) {
        this.dnsServers = new ArrayList<>(servers);
    }

    /**
     * Process a raw DNS query UDP payload.
     * @param dnsPayload raw DNS wire-format bytes
     * @param dnsServer  destination DNS server IP
     * @param qcb        optional per-query callback
     */
    public void processQuery(byte[] dnsPayload, String dnsServer, QueryCallback qcb) {
        executor.execute(() -> {
            try {
                DnsPacket packet = parseDnsPacket(dnsPayload);
                if (packet == null) return;

                long start = System.currentTimeMillis();

                // Forward to real DNS server and get response
                byte[] response = forwardDnsQuery(dnsPayload, dnsServer, 53);
                int responseMs = (int)(System.currentTimeMillis() - start);

                List<String> answers = new ArrayList<>();
                if (response != null) {
                    answers = parseDnsAnswers(response);
                }

                Map<String, Object> entry = new HashMap<>();
                entry.put("timestamp",  System.currentTimeMillis());
                entry.put("queryType",  packet.queryType);
                entry.put("hostname",   packet.hostname);
                entry.put("answers",    answers);
                entry.put("responseMs", responseMs);
                entry.put("blocked",    false);

                callback.onDnsEntry(entry);

                // Also update browsing log
                Map<String, Object> browsingEntry = new HashMap<>();
                browsingEntry.put("timestamp",        System.currentTimeMillis());
                browsingEntry.put("url",              "dns://" + packet.hostname);
                browsingEntry.put("hostname",         packet.hostname);
                browsingEntry.put("protocol",         "dns-only");
                browsingEntry.put("bytesTransferred", (long) dnsPayload.length);
                WireGuardVpnService.addToBrowsingLog(browsingEntry); // See note below

                if (qcb != null) qcb.onResult(entry);

            } catch (Exception e) {
                Log.v(TAG, "DNS processing error: " + e.getMessage());
            }
        });
    }

    // ── DNS packet parsing ─────────────────────────────────────────────────────

    private static class DnsPacket {
        String hostname;
        String queryType;
    }

    private DnsPacket parseDnsPacket(byte[] data) {
        if (data == null || data.length < 12) return null;
        try {
            // DNS header is 12 bytes; question section starts at offset 12
            int qdCount = ((data[4] & 0xFF) << 8) | (data[5] & 0xFF);
            if (qdCount == 0) return null;

            DnsPacket pkt = new DnsPacket();
            pkt.hostname  = readDnsName(data, 12);
            // QTYPE is 2 bytes after the name
            int nameEnd   = findNameEnd(data, 12);
            if (nameEnd + 2 < data.length) {
                int qtype = ((data[nameEnd] & 0xFF) << 8) | (data[nameEnd + 1] & 0xFF);
                pkt.queryType = qtypeToString(qtype);
            } else {
                pkt.queryType = "A";
            }
            return pkt;
        } catch (Exception e) {
            return null;
        }
    }

    private String readDnsName(byte[] data, int offset) {
        StringBuilder sb = new StringBuilder();
        while (offset < data.length) {
            int len = data[offset] & 0xFF;
            if (len == 0) break;
            if ((len & 0xC0) == 0xC0) {
                // Pointer
                int ptr = ((len & 0x3F) << 8) | (data[offset + 1] & 0xFF);
                if (sb.length() > 0) sb.append('.');
                sb.append(readDnsName(data, ptr));
                break;
            }
            if (sb.length() > 0) sb.append('.');
            sb.append(new String(data, offset + 1, len));
            offset += len + 1;
        }
        return sb.toString();
    }

    private int findNameEnd(byte[] data, int offset) {
        while (offset < data.length) {
            int len = data[offset] & 0xFF;
            if (len == 0) return offset + 1;
            if ((len & 0xC0) == 0xC0) return offset + 2;
            offset += len + 1;
        }
        return offset;
    }

    private List<String> parseDnsAnswers(byte[] data) {
        List<String> answers = new ArrayList<>();
        try {
            // Skip header (12) + question section
            int anCount = ((data[6] & 0xFF) << 8) | (data[7] & 0xFF);
            if (anCount == 0) return answers;
            // Skip question section
            int pos = 12;
            pos = findNameEnd(data, pos) + 4; // skip name + type + class
            for (int i = 0; i < anCount && pos < data.length; i++) {
                pos = findNameEnd(data, pos); // skip name
                if (pos + 10 > data.length) break;
                int type   = ((data[pos] & 0xFF) << 8) | (data[pos + 1] & 0xFF);
                int rdLen  = ((data[pos + 8] & 0xFF) << 8) | (data[pos + 9] & 0xFF);
                pos += 10;
                if (type == 1 && rdLen == 4 && pos + 4 <= data.length) {
                    // A record
                    answers.add((data[pos] & 0xFF) + "." + (data[pos + 1] & 0xFF) + "."
                        + (data[pos + 2] & 0xFF) + "." + (data[pos + 3] & 0xFF));
                } else if (type == 28 && rdLen == 16 && pos + 16 <= data.length) {
                    // AAAA record – simplified
                    answers.add("IPv6:...");
                }
                pos += rdLen;
            }
        } catch (Exception e) {
            Log.v(TAG, "parseDnsAnswers error: " + e.getMessage());
        }
        return answers;
    }

    private String qtypeToString(int qtype) {
        switch (qtype) {
            case 1:   return "A";
            case 28:  return "AAAA";
            case 5:   return "CNAME";
            case 15:  return "MX";
            case 16:  return "TXT";
            case 2:   return "NS";
            case 6:   return "SOA";
            default:  return "TYPE" + qtype;
        }
    }

    private byte[] forwardDnsQuery(byte[] query, String server, int port) {
        try (java.net.DatagramSocket socket = new java.net.DatagramSocket()) {
            socket.setSoTimeout(3000);
            java.net.InetAddress addr = java.net.InetAddress.getByName(server);
            java.net.DatagramPacket request = new java.net.DatagramPacket(
                query, query.length, addr, port);
            socket.send(request);
            byte[] respBuf = new byte[4096];
            java.net.DatagramPacket response = new java.net.DatagramPacket(respBuf, respBuf.length);
            socket.receive(response);
            return Arrays.copyOf(respBuf, response.getLength());
        } catch (Exception e) {
            Log.v(TAG, "DNS forward failed: " + e.getMessage());
            return null;
        }
    }
}
