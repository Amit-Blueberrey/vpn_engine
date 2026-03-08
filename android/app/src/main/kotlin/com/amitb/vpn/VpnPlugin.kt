package com.amitb.vpn

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

/**
 * VpnPlugin.kt
 *
 * Flutter MethodChannel + EventChannel bridge.
 * - METHOD_CHANNEL "com.amitb.vpn/engine":
 *     "prepare"    → Launches the VPN permission intent (required by Android).
 *     "startVpn"   → Starts WireGuardVpnService with the config string.
 *     "stopVpn"    → Stops the service.
 * - EVENT_CHANNEL "com.amitb.vpn/tunnel_fd":
 *     Emits Map { "fd": Int, "config": String } once the TUN is ready.
 *     Dart FFI listens here to receive the fd before calling wg_tunnel_start().
 */
class VpnPlugin(
    private val activity: Activity,
    flutterEngine: FlutterEngine
) : PluginRegistry.ActivityResultListener {

    companion object {
        private const val METHOD_CHANNEL_NAME = "com.amitb.vpn/engine"
        private const val EVENT_CHANNEL_NAME  = "com.amitb.vpn/tunnel_fd"
        private const val VPN_PREPARE_REQUEST = 1001

        // Exposed so WireGuardVpnService can push events.
        var tunnelFdSink: EventChannel.EventSink? = null
    }

    private var pendingResult: MethodChannel.Result? = null

    init {
        // Method channel
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            METHOD_CHANNEL_NAME
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "prepare" -> prepare(result)
                "startVpn" -> startVpn(call, result)
                "stopVpn"  -> stopVpn(result)
                else -> result.notImplemented()
            }
        }

        // Event channel – used to stream the TUN fd back to Dart.
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            EVENT_CHANNEL_NAME
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(args: Any?, sink: EventChannel.EventSink?) {
                tunnelFdSink = sink
            }
            override fun onCancel(args: Any?) {
                tunnelFdSink = null
            }
        })
    }

    private fun prepare(result: MethodChannel.Result) {
        val intent = VpnService.prepare(activity)
        if (intent == null) {
            // Already authorized.
            result.success(true)
        } else {
            pendingResult = result
            activity.startActivityForResult(intent, VPN_PREPARE_REQUEST)
        }
    }

    private fun startVpn(call: MethodCall, result: MethodChannel.Result) {
        val config = call.argument<String>("config") ?: run {
            result.error("MISSING_CONFIG", "Config string is required", null)
            return
        }
        val dns = call.argument<String>("dns") ?: "1.1.1.1"

        val intent = Intent(activity, WireGuardVpnService::class.java).apply {
            action = WireGuardVpnService.ACTION_START
            putExtra(WireGuardVpnService.EXTRA_CONFIG, config)
            putExtra(WireGuardVpnService.EXTRA_DNS,    dns)
        }
        activity.startService(intent)
        result.success(null)
    }

    private fun stopVpn(result: MethodChannel.Result) {
        val intent = Intent(activity, WireGuardVpnService::class.java).apply {
            action = WireGuardVpnService.ACTION_STOP
        }
        activity.startService(intent)
        result.success(null)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode == VPN_PREPARE_REQUEST) {
            pendingResult?.success(resultCode == Activity.RESULT_OK)
            pendingResult = null
            return true
        }
        return false
    }
}
