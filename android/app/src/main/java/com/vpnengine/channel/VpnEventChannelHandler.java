// android/app/src/main/java/com/vpnengine/channel/VpnEventChannelHandler.java
package com.vpnengine.channel;

import android.app.Activity;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.os.Build;
import android.util.Log;

import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.EventChannel;

import java.util.Map;

/**
 * Manages three EventChannels:
 *  1. com.vpnengine/vpn_state   → VPN connection state changes
 *  2. com.vpnengine/traffic_log → Per-connection traffic events
 *  3. com.vpnengine/dns_log     → DNS query events
 *
 * The native VpnService broadcasts Intents → this handler forwards to Flutter.
 */
public class VpnEventChannelHandler {

    private static final String TAG = "VpnEventChannel";

    // Channel names (must match Dart side)
    public static final String STATE_CHANNEL   = "com.vpnengine/vpn_state";
    public static final String TRAFFIC_CHANNEL = "com.vpnengine/traffic_log";
    public static final String DNS_CHANNEL     = "com.vpnengine/dns_log";

    // Broadcast action names (from WireGuardVpnService)
    public static final String ACTION_STATE_CHANGE   = "com.vpnengine.VPN_STATE";
    public static final String ACTION_TRAFFIC_UPDATE = "com.vpnengine.TRAFFIC_LOG";
    public static final String ACTION_DNS_UPDATE     = "com.vpnengine.DNS_LOG";

    private final Activity activity;
    private final FlutterEngine flutterEngine;

    private EventChannel stateChannel;
    private EventChannel trafficChannel;
    private EventChannel dnsChannel;

    private EventChannel.EventSink stateSink;
    private EventChannel.EventSink trafficSink;
    private EventChannel.EventSink dnsSink;

    // Broadcast receivers
    private BroadcastReceiver stateReceiver;
    private BroadcastReceiver trafficReceiver;
    private BroadcastReceiver dnsReceiver;

    public VpnEventChannelHandler(Activity activity, FlutterEngine engine) {
        this.activity = activity;
        this.flutterEngine = engine;
    }

    public void register() {
        registerStateChannel();
        registerTrafficChannel();
        registerDnsChannel();
        Log.i(TAG, "All event channels registered");
    }

    // ─── State Channel ─────────────────────────────────────────────────────────

    private void registerStateChannel() {
        stateChannel = new EventChannel(
            flutterEngine.getDartExecutor().getBinaryMessenger(),
            STATE_CHANNEL
        );
        stateChannel.setStreamHandler(new EventChannel.StreamHandler() {
            @Override
            public void onListen(Object args, EventChannel.EventSink sink) {
                Log.d(TAG, "State channel: Flutter listening");
                stateSink = sink;
                stateReceiver = new BroadcastReceiver() {
                    @Override
                    public void onReceive(Context ctx, Intent intent) {
                        if (stateSink == null) return;
                        Map<String, Object> stateMap = extractStateFromIntent(intent);
                        activity.runOnUiThread(() -> stateSink.success(stateMap));
                    }
                };
                registerReceiver(stateReceiver, ACTION_STATE_CHANGE);
            }

            @Override
            public void onCancel(Object args) {
                Log.d(TAG, "State channel: Flutter cancelled");
                stateSink = null;
                safeUnregister(stateReceiver);
                stateReceiver = null;
            }
        });
    }

    // ─── Traffic Channel ───────────────────────────────────────────────────────

    private void registerTrafficChannel() {
        trafficChannel = new EventChannel(
            flutterEngine.getDartExecutor().getBinaryMessenger(),
            TRAFFIC_CHANNEL
        );
        trafficChannel.setStreamHandler(new EventChannel.StreamHandler() {
            @Override
            public void onListen(Object args, EventChannel.EventSink sink) {
                Log.d(TAG, "Traffic channel: Flutter listening");
                trafficSink = sink;
                trafficReceiver = new BroadcastReceiver() {
                    @Override
                    public void onReceive(Context ctx, Intent intent) {
                        if (trafficSink == null) return;
                        Map<String, Object> entry = extractTrafficFromIntent(intent);
                        activity.runOnUiThread(() -> trafficSink.success(entry));
                    }
                };
                registerReceiver(trafficReceiver, ACTION_TRAFFIC_UPDATE);
            }

            @Override
            public void onCancel(Object args) {
                trafficSink = null;
                safeUnregister(trafficReceiver);
                trafficReceiver = null;
            }
        });
    }

    // ─── DNS Channel ───────────────────────────────────────────────────────────

    private void registerDnsChannel() {
        dnsChannel = new EventChannel(
            flutterEngine.getDartExecutor().getBinaryMessenger(),
            DNS_CHANNEL
        );
        dnsChannel.setStreamHandler(new EventChannel.StreamHandler() {
            @Override
            public void onListen(Object args, EventChannel.EventSink sink) {
                Log.d(TAG, "DNS channel: Flutter listening");
                dnsSink = sink;
                dnsReceiver = new BroadcastReceiver() {
                    @Override
                    public void onReceive(Context ctx, Intent intent) {
                        if (dnsSink == null) return;
                        Map<String, Object> entry = extractDnsFromIntent(intent);
                        activity.runOnUiThread(() -> dnsSink.success(entry));
                    }
                };
                registerReceiver(dnsReceiver, ACTION_DNS_UPDATE);
            }

            @Override
            public void onCancel(Object args) {
                dnsSink = null;
                safeUnregister(dnsReceiver);
                dnsReceiver = null;
            }
        });
    }

    // ─── Intent → Map extractors ───────────────────────────────────────────────

    private Map<String, Object> extractStateFromIntent(Intent intent) {
        Map<String, Object> map = new java.util.HashMap<>();
        map.put("state",          intent.getStringExtra("state"));
        map.put("tunnelIp",       intent.getStringExtra("tunnelIp"));
        map.put("serverEndpoint", intent.getStringExtra("serverEndpoint"));
        map.put("serverPublicKey",intent.getStringExtra("serverPublicKey"));
        map.put("interfaceName",  intent.getStringExtra("interfaceName"));
        map.put("errorMessage",   intent.getStringExtra("errorMessage"));
        long connectedAt = intent.getLongExtra("connectedAt", 0);
        if (connectedAt > 0) map.put("connectedAt", connectedAt);
        return map;
    }

    private Map<String, Object> extractTrafficFromIntent(Intent intent) {
        Map<String, Object> map = new java.util.HashMap<>();
        map.put("timestamp", intent.getLongExtra("timestamp", System.currentTimeMillis()));
        map.put("protocol",  intent.getStringExtra("protocol"));
        map.put("srcIp",     intent.getStringExtra("srcIp"));
        map.put("srcPort",   intent.getIntExtra("srcPort", 0));
        map.put("dstIp",     intent.getStringExtra("dstIp"));
        map.put("dstPort",   intent.getIntExtra("dstPort", 0));
        map.put("bytes",     intent.getLongExtra("bytes", 0));
        map.put("hostname",  intent.getStringExtra("hostname"));
        map.put("direction", intent.getStringExtra("direction"));
        return map;
    }

    private Map<String, Object> extractDnsFromIntent(Intent intent) {
        Map<String, Object> map = new java.util.HashMap<>();
        map.put("timestamp",  intent.getLongExtra("timestamp", System.currentTimeMillis()));
        map.put("queryType",  intent.getStringExtra("queryType"));
        map.put("hostname",   intent.getStringExtra("hostname"));
        map.put("answers",    intent.getStringArrayListExtra("answers"));
        map.put("responseMs", intent.getIntExtra("responseMs", 0));
        map.put("blocked",    intent.getBooleanExtra("blocked", false));
        return map;
    }

    // ─── Helpers ───────────────────────────────────────────────────────────────

    private void registerReceiver(BroadcastReceiver receiver, String action) {
        IntentFilter filter = new IntentFilter(action);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            activity.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED);
        } else {
            activity.registerReceiver(receiver, filter);
        }
    }

    private void safeUnregister(BroadcastReceiver receiver) {
        if (receiver != null) {
            try {
                activity.unregisterReceiver(receiver);
            } catch (Exception ignored) {}
        }
    }

    public void cleanup() {
        safeUnregister(stateReceiver);
        safeUnregister(trafficReceiver);
        safeUnregister(dnsReceiver);
        if (stateChannel != null) stateChannel.setStreamHandler(null);
        if (trafficChannel != null) trafficChannel.setStreamHandler(null);
        if (dnsChannel != null) dnsChannel.setStreamHandler(null);
    }
}
