// android/app/src/main/java/com/vpnengine/service/WireGuardVpnService.java
package com.vpnengine.service;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.net.VpnService;
import android.os.Build;
import android.os.IBinder;
import android.os.ParcelFileDescriptor;
import android.util.Log;

import androidx.core.app.NotificationCompat;

import com.vpnengine.MainActivity;
import com.vpnengine.channel.VpnEventChannelHandler;
import com.vpnengine.model.WgConfig;
import com.vpnengine.tunnel.WireGuardTunnel;
import com.vpnengine.tunnel.PacketProcessor;
import com.vpnengine.utils.DnsInterceptor;

import org.json.JSONObject;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CopyOnWriteArrayList;

/**
 * Core Android VPN service.
 * - Extends android.net.VpnService
 * - Creates the TUN interface via Builder
 * - Starts WireGuardTunnel for crypto/tunneling
 * - Captures and logs DNS queries and connection metadata
 * - Broadcasts state/traffic/DNS events to Flutter via EventChannels
 */
public class WireGuardVpnService extends VpnService {

    private static final String TAG = "WireGuardVpnService";
    private static final String NOTIF_CHANNEL = "vpn_channel";
    private static final int NOTIF_ID = 1001;

    public static final String ACTION_CONNECT    = "com.vpnengine.CONNECT";
    public static final String ACTION_DISCONNECT = "com.vpnengine.DISCONNECT";
    public static final String EXTRA_CONFIG_JSON = "config_json";

    // ── Static shared state (accessible from channel handlers) ────────────────
    private static volatile String currentState = "disconnected";
    private static volatile String currentTunnelIp;
    private static volatile String currentEndpoint;
    private static volatile String currentServerKey;
    private static volatile long connectedAt;
    private static volatile WireGuardVpnService instance;

    // Browsing log (thread-safe, capped)
    private static final CopyOnWriteArrayList<Map<String, Object>> browsingLog =
        new CopyOnWriteArrayList<>();
    private static final int MAX_BROWSING_LOG = 1000;

    // ── Instance members ──────────────────────────────────────────────────────
    private ParcelFileDescriptor tunFd;
    private WireGuardTunnel wgTunnel;
    private PacketProcessor packetProcessor;
    private DnsInterceptor dnsInterceptor;
    private Thread tunnelThread;

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    @Override
    public void onCreate() {
        super.onCreate();
        instance = this;
        createNotificationChannel();
        Log.i(TAG, "WireGuardVpnService created");
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent == null) return START_NOT_STICKY;

        String action = intent.getAction();
        Log.i(TAG, "onStartCommand action: " + action);

        if (ACTION_CONNECT.equals(action)) {
            startForeground(NOTIF_ID, buildNotification("Connecting..."));
            String configJson = intent.getStringExtra(EXTRA_CONFIG_JSON);
            startTunnel(configJson);
        } else if (ACTION_DISCONNECT.equals(action)) {
            stopTunnel();
            stopForeground(true);
            stopSelf();
        }
        return START_STICKY;
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    @Override
    public void onDestroy() {
        stopTunnel();
        instance = null;
        super.onDestroy();
        Log.i(TAG, "WireGuardVpnService destroyed");
    }

    // ── Tunnel Start / Stop ───────────────────────────────────────────────────

    private void startTunnel(String configJson) {
        new Thread(() -> {
            try {
                broadcastState("connecting", null, null, null, null, null);

                WgConfig config = WgConfig.fromJson(new JSONObject(configJson));

                // Build the TUN interface
                Builder builder = new Builder();
                builder.setSession(config.tunnelName);
                builder.addAddress(config.address.split("/")[0],
                    Integer.parseInt(config.address.split("/")[1]));
                if (config.addressV6 != null && !config.addressV6.isEmpty()) {
                    builder.addAddress(config.addressV6.split("/")[0],
                        Integer.parseInt(config.addressV6.split("/")[1]));
                }
                // DNS servers
                for (String dns : config.dnsServers) {
                    builder.addDnsServer(dns);
                }
                // Routes (allowed IPs)
                for (String allowedIp : config.allowedIPs) {
                    String[] parts = allowedIp.trim().split("/");
                    if (parts.length == 2) {
                        try {
                            builder.addRoute(parts[0], Integer.parseInt(parts[1]));
                        } catch (Exception e) {
                            Log.w(TAG, "Could not add route: " + allowedIp);
                        }
                    }
                }
                builder.setMtu(config.mtu);
                builder.setBlocking(true);
                // Allow bypass for specific apps if needed
                // builder.addDisallowedApplication("com.some.app");

                tunFd = builder.establish();
                if (tunFd == null) {
                    broadcastState("error", null, null, null, "TUN interface could not be established", null);
                    return;
                }

                Log.i(TAG, "TUN interface established: fd=" + tunFd.getFd());

                // Start WireGuard tunnel (userspace or kernel via JNI)
                wgTunnel = new WireGuardTunnel();
                wgTunnel.setConfig(config);
                wgTunnel.setTunFd(tunFd.getFd());
                wgTunnel.start();

                // Start packet processor for logging
                dnsInterceptor = new DnsInterceptor(getApplicationContext(), (entry) -> {
                    addToBrowsingLog(entry);
                    broadcastDnsEntry(entry);
                });
                packetProcessor = new PacketProcessor(tunFd, dnsInterceptor, (entry) -> {
                    broadcastTrafficEntry(entry);
                });

                tunnelThread = new Thread(packetProcessor::run, "PacketProcessorThread");
                tunnelThread.setDaemon(true);
                tunnelThread.start();

                // Update state
                currentTunnelIp = config.address;
                currentEndpoint  = config.serverEndpoint;
                currentServerKey = config.serverPublicKey;
                connectedAt      = System.currentTimeMillis();

                broadcastState("connected", currentTunnelIp, currentEndpoint,
                    currentServerKey, null, "wg0");

                updateNotification("Connected – " + config.serverEndpoint);
                Log.i(TAG, "Tunnel started successfully");

            } catch (Exception e) {
                Log.e(TAG, "Tunnel start failed", e);
                broadcastState("error", null, null, null, e.getMessage(), null);
                stopForeground(true);
                stopSelf();
            }
        }, "TunnelStartThread").start();
    }

    private void stopTunnel() {
        Log.i(TAG, "Stopping tunnel...");
        try {
            if (packetProcessor != null) { packetProcessor.stop(); packetProcessor = null; }
            if (tunnelThread != null)    { tunnelThread.interrupt(); tunnelThread = null; }
            if (wgTunnel != null)        { wgTunnel.stop(); wgTunnel = null; }
            if (tunFd != null)           { tunFd.close(); tunFd = null; }
        } catch (Exception e) {
            Log.e(TAG, "Error stopping tunnel", e);
        }
        currentState     = "disconnected";
        currentTunnelIp  = null;
        currentEndpoint  = null;
        connectedAt      = 0;
        broadcastState("disconnected", null, null, null, null, null);
    }

    // ── State Broadcast ───────────────────────────────────────────────────────

    public static void broadcastState(String state, String tunnelIp,
        String endpoint, String serverKey, String errorMsg, String iface) {
        currentState = state;
        if (instance == null) return;
        Intent i = new Intent(VpnEventChannelHandler.ACTION_STATE_CHANGE);
        i.putExtra("state",          state);
        i.putExtra("tunnelIp",       tunnelIp);
        i.putExtra("serverEndpoint", endpoint);
        i.putExtra("serverPublicKey",serverKey);
        i.putExtra("interfaceName",  iface);
        i.putExtra("errorMessage",   errorMsg);
        if (connectedAt > 0) i.putExtra("connectedAt", connectedAt);
        i.setPackage(instance.getPackageName());
        instance.sendBroadcast(i);
    }

    public static void broadcastTrafficEntry(Map<String, Object> entry) {
        if (instance == null) return;
        Intent i = new Intent(VpnEventChannelHandler.ACTION_TRAFFIC_UPDATE);
        for (Map.Entry<String, Object> kv : entry.entrySet()) {
            Object v = kv.getValue();
            if (v instanceof String)  i.putExtra(kv.getKey(), (String) v);
            if (v instanceof Integer) i.putExtra(kv.getKey(), (int) v);
            if (v instanceof Long)    i.putExtra(kv.getKey(), (long) v);
            if (v instanceof Boolean) i.putExtra(kv.getKey(), (boolean) v);
        }
        i.setPackage(instance.getPackageName());
        instance.sendBroadcast(i);
    }

    public static void broadcastDnsEntry(Map<String, Object> entry) {
        if (instance == null) return;
        Intent i = new Intent(VpnEventChannelHandler.ACTION_DNS_UPDATE);
        i.putExtra("timestamp",  (long) entry.getOrDefault("timestamp", 0L));
        i.putExtra("queryType",  (String) entry.getOrDefault("queryType", "A"));
        i.putExtra("hostname",   (String) entry.getOrDefault("hostname", ""));
        i.putStringArrayListExtra("answers",
            new ArrayList<>((List<String>) entry.getOrDefault("answers", new ArrayList<>())));
        i.putExtra("responseMs", (int) entry.getOrDefault("responseMs", 0));
        i.putExtra("blocked",    (boolean) entry.getOrDefault("blocked", false));
        i.setPackage(instance.getPackageName());
        instance.sendBroadcast(i);
    }

    // ── Static API (called from channel handlers) ─────────────────────────────

    public static void initialize(Context ctx) {
        // Pre-load any WireGuard JNI library
        try {
            System.loadLibrary("wg-go"); // WireGuard-Go JNI if using it
        } catch (UnsatisfiedLinkError e) {
            Log.w(TAG, "wg-go native lib not found, using userspace Java fallback");
        }
    }

    public static Map<String, Object> getCurrentStatus() {
        Map<String, Object> m = new HashMap<>();
        m.put("state",          currentState);
        m.put("tunnelIp",       currentTunnelIp);
        m.put("serverEndpoint", currentEndpoint);
        m.put("serverPublicKey",currentServerKey);
        m.put("interfaceName",  currentState.equals("connected") ? "wg0" : null);
        if (connectedAt > 0) m.put("connectedAt", connectedAt);
        return m;
    }

    public static void importConfig(Context ctx, WgConfig config) {
        // Store config to SharedPreferences / file for later connect
        android.content.SharedPreferences prefs =
            ctx.getSharedPreferences("vpn_configs", Context.MODE_PRIVATE);
        prefs.edit().putString("config_" + config.tunnelName, config.toJson()).apply();
    }

    public static void removeConfig(Context ctx, String tunnelName) {
        android.content.SharedPreferences prefs =
            ctx.getSharedPreferences("vpn_configs", Context.MODE_PRIVATE);
        prefs.edit().remove("config_" + tunnelName).apply();
    }

    public static List<Map<String, Object>> getBrowsingLog() {
        return new ArrayList<>(browsingLog);
    }

    public static void clearBrowsingLog() {
        browsingLog.clear();
    }

    public static void setDnsServers(List<String> servers) {
        // Applied on next connection; live reconfiguration requires tunnel restart
        if (instance != null && instance.dnsInterceptor != null) {
            instance.dnsInterceptor.setDnsServers(servers);
        }
    }

    private static void addToBrowsingLog(Map<String, Object> entry) {
        if (browsingLog.size() >= MAX_BROWSING_LOG) {
            browsingLog.remove(0);
        }
        browsingLog.add(entry);
    }

    // ── Notification ──────────────────────────────────────────────────────────

    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel ch = new NotificationChannel(
                NOTIF_CHANNEL, "VPN Status", NotificationManager.IMPORTANCE_LOW
            );
            ch.setDescription("Shows VPN connection status");
            NotificationManager nm = getSystemService(NotificationManager.class);
            if (nm != null) nm.createNotificationChannel(ch);
        }
    }

    private Notification buildNotification(String text) {
        Intent intent = new Intent(this, MainActivity.class);
        PendingIntent pi = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
        );
        return new NotificationCompat.Builder(this, NOTIF_CHANNEL)
            .setContentTitle("VPN Engine")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(pi)
            .setOngoing(true)
            .build();
    }

    private void updateNotification(String text) {
        NotificationManager nm = getSystemService(NotificationManager.class);
        if (nm != null) nm.notify(NOTIF_ID, buildNotification(text));
    }
}
