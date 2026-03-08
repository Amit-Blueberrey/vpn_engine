package com.amitb.vpn

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * BootReceiver.kt
 *
 * Module 2: Auto-reconnect on Device Reboot.
 *
 * Registered in AndroidManifest.xml with:
 *   <action android:name="android.intent.action.BOOT_COMPLETED" />
 *   <action android:name="android.intent.action.MY_PACKAGE_REPLACED" />
 *   <action android:name="android.intent.action.QUICKBOOT_POWERON" /> (HTC devices)
 *
 * When the device reboots, this receiver fires BEFORE the user unlocks the
 * screen. We read the last-used VPN config from encrypted SharedPreferences
 * (stored by the Flutter app via flutter_secure_storage) and restart the tunnel.
 *
 * Flow:
 *   Boot → BootReceiver.onReceive() → start VpnForegroundService
 *        → ForegroundService starts WireGuardVpnService with stored config
 */
class BootReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "VpnBootReceiver"
        const val PREFS_NAME = "vpn_boot_prefs"
        const val KEY_LAST_CONFIG = "last_wg_config"
        const val KEY_LAST_DNS    = "last_dns"
        const val KEY_AUTO_START  = "auto_start_on_boot"
    }

    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        Log.d(TAG, "onReceive: $action")

        val relevantActions = setOf(
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            "android.intent.action.QUICKBOOT_POWERON" // HTC/some OEM devices
        )
        if (action !in relevantActions) return

        // Check if the user opted into "auto-start on boot"
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val autoStart = prefs.getBoolean(KEY_AUTO_START, false)
        if (!autoStart) {
            Log.d(TAG, "Auto-start on boot disabled, skipping.")
            return
        }

        val lastConfig = prefs.getString(KEY_LAST_CONFIG, null) ?: run {
            Log.d(TAG, "No stored VPN config, skipping boot reconnect.")
            return
        }
        val lastDns = prefs.getString(KEY_LAST_DNS, "1.1.1.1") ?: "1.1.1.1"

        Log.d(TAG, "Restarting VPN after boot...")

        // Start the VPN foreground service
        val foregroundIntent = Intent(context, VpnForegroundService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(foregroundIntent)
        } else {
            context.startService(foregroundIntent)
        }

        // After a short delay, start the WireGuard service with the last config.
        // We use Handler because we're in a BroadcastReceiver (no Coroutines here).
        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
            val vpnIntent = Intent(context, WireGuardVpnService::class.java).apply {
                this.action = WireGuardVpnService.ACTION_START
                putExtra(WireGuardVpnService.EXTRA_CONFIG, lastConfig)
                putExtra(WireGuardVpnService.EXTRA_DNS, lastDns)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(vpnIntent)
            } else {
                context.startService(vpnIntent)
            }
        }, 2000) // 2-second delay to allow system to stabilise after boot
    }
}
