package com.amitb.vpn

import android.content.Intent
import android.net.VpnService
import android.os.Binder
import android.os.IBinder
import android.os.ParcelFileDescriptor
import android.util.Log
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * WireGuardVpnService.kt
 *
 * An Android VpnService that:
 *  1. Calls VpnService.Builder to create a TUN fd.
 *  2. Passes the raw fd integer to our native wireguard core via MethodChannel.
 *  3. Reports connection state back to Flutter via EventChannel.
 *
 * The actual WireGuard cryptography and tunnel management runs in the
 * native libwireguard.so via Dart FFI — this service only handles the
 * OS-side permission grant and fd lifecycle.
 */
class WireGuardVpnService : VpnService() {

    companion object {
        private const val TAG = "WgVpnService"
        const val ACTION_START = "com.amitb.vpn.START"
        const val ACTION_STOP  = "com.amitb.vpn.STOP"
        const val EXTRA_CONFIG = "wg_config"
        const val EXTRA_DNS    = "wg_dns"
    }

    private var tunFd: ParcelFileDescriptor? = null

    // The Binder lets MainActivity retrieve the raw fd.
    inner class LocalBinder : Binder() {
        fun getRawFd(): Int = tunFd?.fd ?: -1
    }
    private val binder = LocalBinder()

    override fun onBind(intent: Intent?): IBinder = binder

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val config = intent.getStringExtra(EXTRA_CONFIG) ?: return START_NOT_STICKY
                val dns    = intent.getStringExtra(EXTRA_DNS) ?: "1.1.1.1"
                startTunnel(config, dns)
            }
            ACTION_STOP -> stopTunnel()
        }
        return START_STICKY
    }

    private fun startTunnel(wgConfig: String, dns: String) {
        Log.d(TAG, "startTunnel()")

        // Parse address from config (line: Address = 10.x.x.x/32)
        val address = wgConfig.lines()
            .firstOrNull { it.trim().startsWith("Address") }
            ?.split("=")?.getOrNull(1)?.trim() ?: "10.66.66.2/32"

        val parts = address.split("/")
        val ip    = parts[0]
        val prefix = parts.getOrNull(1)?.toIntOrNull() ?: 32

        try {
            val builder = Builder()
                .setSession("WireGuard VPN")
                .addAddress(ip, prefix)
                .addRoute("0.0.0.0", 0)         // Full-tunnel IPv4
                .addRoute("::", 0)              // Full-tunnel IPv6
                .addDnsServer(dns)
                .setMtu(1420)
                .setBlocking(false)             // Non-blocking TUN so dart reads it asynchronously

            tunFd = builder.establish()
            Log.d(TAG, "TUN fd established: ${tunFd?.fd}")

            // fd is now readable by the Dart FFI layer via the MethodChannel response.
            sendFdToFlutter(tunFd?.fd ?: -1, wgConfig)

        } catch (e: Exception) {
            Log.e(TAG, "Failed to establish TUN: ${e.message}")
        }
    }

    private fun sendFdToFlutter(fd: Int, config: String) {
        // Broadcast the fd via a static EventSink exposed by VpnPlugin.
        VpnPlugin.tunnelFdSink?.success(
            mapOf("fd" to fd, "config" to config)
        )
    }

    private fun stopTunnel() {
        Log.d(TAG, "stopTunnel()")
        tunFd?.close()
        tunFd = null
        stopSelf()
    }

    override fun onRevoke() {
        // System revoked the VPN permission (e.g. user turned it off in Settings).
        stopTunnel()
        super.onRevoke()
    }
}
