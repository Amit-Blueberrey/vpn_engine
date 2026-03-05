// android/app/src/main/java/com/vpnengine/channel/VpnMethodChannelHandler.java
package com.vpnengine.channel;

import android.app.Activity;
import android.content.Intent;
import android.net.VpnService;
import android.util.Log;

import androidx.annotation.NonNull;

import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

import com.vpnengine.service.WireGuardVpnService;
import com.vpnengine.tunnel.WireGuardTunnel;
import com.vpnengine.utils.KeyGeneratorUtil;
import com.vpnengine.utils.PingUtil;
import com.vpnengine.model.WgConfig;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

public class VpnMethodChannelHandler implements MethodChannel.MethodCallHandler {

    private static final String TAG = "VpnMethodChannel";
    public static final String CHANNEL_NAME = "com.vpnengine/wireguard";
    private static final int VPN_PERMISSION_REQUEST = 1001;

    private final Activity activity;
    private MethodChannel channel;
    private MethodChannel.Result pendingPermissionResult;

    public VpnMethodChannelHandler(Activity activity, FlutterEngine engine) {
        this.activity = activity;
    }

    public void register() {
        channel = new MethodChannel(
            getFlutterEngine().getDartExecutor().getBinaryMessenger(),
            CHANNEL_NAME
        );
        channel.setMethodCallHandler(this);
        Log.i(TAG, "VPN method channel registered");
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        Log.d(TAG, "onMethodCall: " + call.method);
        switch (call.method) {
            case "initialize":
                handleInitialize(result);
                break;
            case "connect":
                handleConnect(call, result);
                break;
            case "disconnect":
                handleDisconnect(result);
                break;
            case "getStatus":
                handleGetStatus(result);
                break;
            case "getTrafficStats":
                handleGetTrafficStats(result);
                break;
            case "generateKeyPair":
                handleGenerateKeyPair(result);
                break;
            case "importConfig":
                handleImportConfig(call, result);
                break;
            case "removeConfig":
                handleRemoveConfig(call, result);
                break;
            case "isPermissionGranted":
                handleIsPermissionGranted(result);
                break;
            case "requestPermission":
                handleRequestPermission(result);
                break;
            case "checkTunInterface":
                handleCheckTunInterface(result);
                break;
            case "getActiveInterface":
                handleGetActiveInterface(result);
                break;
            case "listPeers":
                handleListPeers(result);
                break;
            case "getBrowsingLog":
                handleGetBrowsingLog(result);
                break;
            case "clearBrowsingLog":
                handleClearBrowsingLog(result);
                break;
            case "setDnsServers":
                handleSetDnsServers(call, result);
                break;
            case "pingServer":
                handlePingServer(call, result);
                break;
            default:
                result.notImplemented();
        }
    }

    // ─── Handlers ──────────────────────────────────────────────────────────────

    private void handleInitialize(MethodChannel.Result result) {
        try {
            WireGuardVpnService.initialize(activity.getApplicationContext());
            Log.i(TAG, "WireGuard engine initialized");
            result.success(true);
        } catch (Exception e) {
            Log.e(TAG, "Initialize failed", e);
            result.success(false);
        }
    }

    private void handleConnect(MethodCall call, MethodChannel.Result result) {
        try {
            Map<String, Object> args = (Map<String, Object>) call.arguments;
            WgConfig config = WgConfig.fromMap(args);

            Log.i(TAG, "Connecting to: " + config.serverEndpoint);

            // Start the foreground VPN service
            Intent serviceIntent = new Intent(activity, WireGuardVpnService.class);
            serviceIntent.setAction(WireGuardVpnService.ACTION_CONNECT);
            serviceIntent.putExtra(WireGuardVpnService.EXTRA_CONFIG_JSON, config.toJson());
            activity.startForegroundService(serviceIntent);

            Map<String, Object> res = new HashMap<>();
            res.put("success", true);
            res.put("message", "Connecting...");
            result.success(res);
        } catch (Exception e) {
            Log.e(TAG, "Connect failed", e);
            Map<String, Object> res = new HashMap<>();
            res.put("success", false);
            res.put("message", e.getMessage());
            result.success(res);
        }
    }

    private void handleDisconnect(MethodChannel.Result result) {
        try {
            Intent serviceIntent = new Intent(activity, WireGuardVpnService.class);
            serviceIntent.setAction(WireGuardVpnService.ACTION_DISCONNECT);
            activity.startService(serviceIntent);
            result.success(true);
        } catch (Exception e) {
            Log.e(TAG, "Disconnect failed", e);
            result.success(false);
        }
    }

    private void handleGetStatus(MethodChannel.Result result) {
        try {
            Map<String, Object> status = WireGuardVpnService.getCurrentStatus();
            result.success(status);
        } catch (Exception e) {
            Log.e(TAG, "GetStatus failed", e);
            Map<String, Object> s = new HashMap<>();
            s.put("state", "disconnected");
            result.success(s);
        }
    }

    private void handleGetTrafficStats(MethodChannel.Result result) {
        try {
            Map<String, Object> stats = WireGuardTunnel.getTrafficStats();
            result.success(stats);
        } catch (Exception e) {
            Log.e(TAG, "GetTrafficStats failed", e);
            Map<String, Object> empty = new HashMap<>();
            empty.put("rxBytes", 0L);
            empty.put("txBytes", 0L);
            empty.put("rxPackets", 0L);
            empty.put("txPackets", 0L);
            empty.put("rxRateBps", 0.0);
            empty.put("txRateBps", 0.0);
            empty.put("timestamp", System.currentTimeMillis());
            result.success(empty);
        }
    }

    private void handleGenerateKeyPair(MethodChannel.Result result) {
        try {
            Map<String, String> keys = KeyGeneratorUtil.generateWireGuardKeyPair();
            Log.i(TAG, "Generated keypair, public key: " + keys.get("publicKey"));
            result.success(keys);
        } catch (Exception e) {
            Log.e(TAG, "Key generation failed", e);
            result.error("KEY_GEN_ERROR", e.getMessage(), null);
        }
    }

    private void handleImportConfig(MethodCall call, MethodChannel.Result result) {
        try {
            Map<String, Object> args = (Map<String, Object>) call.arguments;
            WgConfig config = WgConfig.fromMap(args);
            WireGuardVpnService.importConfig(activity.getApplicationContext(), config);
            result.success(true);
        } catch (Exception e) {
            Log.e(TAG, "ImportConfig failed", e);
            result.success(false);
        }
    }

    private void handleRemoveConfig(MethodCall call, MethodChannel.Result result) {
        try {
            String tunnelName = call.argument("tunnelName");
            WireGuardVpnService.removeConfig(activity.getApplicationContext(), tunnelName);
            result.success(true);
        } catch (Exception e) {
            result.success(false);
        }
    }

    private void handleIsPermissionGranted(MethodChannel.Result result) {
        Intent intent = VpnService.prepare(activity.getApplicationContext());
        result.success(intent == null); // null = already granted
    }

    private void handleRequestPermission(MethodChannel.Result result) {
        Intent intent = VpnService.prepare(activity);
        if (intent == null) {
            result.success(true); // already granted
        } else {
            pendingPermissionResult = result;
            activity.startActivityForResult(intent, VPN_PERMISSION_REQUEST);
        }
    }

    /** Called from Activity.onActivityResult */
    public void onActivityResult(int requestCode, int resultCode, Intent data) {
        if (requestCode == VPN_PERMISSION_REQUEST && pendingPermissionResult != null) {
            boolean granted = resultCode == Activity.RESULT_OK;
            pendingPermissionResult.success(granted);
            pendingPermissionResult = null;
        }
    }

    private void handleCheckTunInterface(MethodChannel.Result result) {
        result.success(WireGuardTunnel.isTunnelActive());
    }

    private void handleGetActiveInterface(MethodChannel.Result result) {
        result.success(WireGuardTunnel.getActiveInterfaceName());
    }

    private void handleListPeers(MethodChannel.Result result) {
        try {
            List<Map<String, Object>> peers = WireGuardTunnel.listPeers();
            result.success(peers);
        } catch (Exception e) {
            result.success(new java.util.ArrayList<>());
        }
    }

    private void handleGetBrowsingLog(MethodChannel.Result result) {
        try {
            List<Map<String, Object>> log =
                WireGuardVpnService.getBrowsingLog();
            result.success(log);
        } catch (Exception e) {
            result.success(new java.util.ArrayList<>());
        }
    }

    private void handleClearBrowsingLog(MethodChannel.Result result) {
        WireGuardVpnService.clearBrowsingLog();
        result.success(null);
    }

    private void handleSetDnsServers(MethodCall call, MethodChannel.Result result) {
        try {
            List<String> servers = call.argument("dnsServers");
            WireGuardVpnService.setDnsServers(servers);
            result.success(true);
        } catch (Exception e) {
            result.success(false);
        }
    }

    private void handlePingServer(MethodCall call, MethodChannel.Result result) {
        String host = call.argument("host");
        int port = call.argument("port");
        new Thread(() -> {
            int ms = PingUtil.pingHost(host, port);
            activity.runOnUiThread(() -> result.success(ms));
        }).start();
    }

    private FlutterEngine getFlutterEngine() {
        // Access engine from the hosting activity
        return ((io.flutter.embedding.android.FlutterActivity) activity).getFlutterEngine();
    }

    public void cleanup() {
        if (channel != null) channel.setMethodCallHandler(null);
    }
}
