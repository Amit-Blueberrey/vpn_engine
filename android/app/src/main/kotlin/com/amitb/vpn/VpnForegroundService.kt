package com.amitb.vpn

import android.app.*
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.IBinder
import android.os.PowerManager
import android.os.Build
import androidx.annotation.RequiresApi
import androidx.core.app.NotificationCompat
import android.util.Log
import kotlinx.coroutines.*

/**
 * VpnForegroundService.kt
 *
 * Module 2: Bulletproof Android Background Execution.
 *
 * Features:
 *  - Persistent Foreground Service (cannot be killed by Android without
 *    user explicit action in Settings → Apps; it is also un-swipeable from
 *    the notification shade by default as a system-priority notification).
 *  - WakeLock: Keeps the CPU active while the VPN tunnel is maintained.
 *  - Live Rx/Tx stats injected into the notification every 2 seconds.
 *  - Network change listener (ConnectivityManager.NetworkCallback) that
 *    triggers automatic reconnect when switching Wi-Fi ↔ Cellular.
 *  - Integrated with WireGuardVpnService lifecycle.
 *
 * Thread model: Main thread for lifecycle; a CoroutineScope with
 *   Dispatchers.IO for the stats update loop (so it doesn't block main).
 */
class VpnForegroundService : Service() {

    companion object {
        private const val TAG               = "VpnForegroundSvc"
        const val  CHANNEL_ID               = "wg_vpn_channel"
        const val  CHANNEL_NAME             = "WireGuard VPN Status"
        const val  NOTIFICATION_ID          = 1337
        const val  ACTION_UPDATE_STATS      = "com.amitb.vpn.UPDATE_STATS"
        const val  EXTRA_RX                 = "rx_bytes"
        const val  EXTRA_TX                 = "tx_bytes"

        private const val WAKELOCK_TAG      = "VpnEngine:WakeLock"
        private const val STATS_INTERVAL_MS = 2000L
    }

    // ── Service Infrastructure ────────────────────────────────────────────────
    private val serviceScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var wakeLock: PowerManager.WakeLock? = null
    private var statsJob: Job? = null

    // Running stats counters (updated via Intent/EventChannel from Dart FFI)
    @Volatile private var rxBytes: Long = 0
    @Volatile private var txBytes: Long = 0

    // Network change listener for automatic reconnect
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private lateinit var connectivityManager: ConnectivityManager

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    override fun onCreate() {
        super.onCreate()
        connectivityManager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        createNotificationChannel()
        acquireWakeLock()
        registerNetworkCallback()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_UPDATE_STATS -> {
                rxBytes = intent.getLongExtra(EXTRA_RX, 0)
                txBytes = intent.getLongExtra(EXTRA_TX, 0)
            }
        }

        // Move to foreground immediately — Android forbids >10s delay.
        startForeground(NOTIFICATION_ID, buildNotification())

        // Start/restart the periodic notification updater.
        startStatsLoop()

        // START_STICKY: if the OS kills us (OOM), restart immediately.
        return START_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        statsJob?.cancel()
        serviceScope.cancel()
        releaseWakeLock()
        unregisterNetworkCallback()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // ── Notification ──────────────────────────────────────────────────────────

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val chan = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW  // LOW = no sound, but persistent
            ).apply {
                description = "Shows active WireGuard VPN connection status"
                setShowBadge(false)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            val nm = getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(chan)
        }
    }

    private fun buildNotification(): Notification {
        val mainIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pi = PendingIntent.getActivity(
            this, 0, mainIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val rxStr = formatBytes(rxBytes)
        val txStr = formatBytes(txBytes)

        // Disconnect action shown in the notification
        val stopIntent = Intent(this, WireGuardVpnService::class.java).apply {
            action = WireGuardVpnService.ACTION_STOP
        }
        val stopPi = PendingIntent.getService(
            this, 1, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("🔐 WireGuard VPN — Connected")
            .setContentText("↓ $rxStr   ↑ $txStr")
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentIntent(pi)
            .setOngoing(true)                    // Un-swipeable by user
            .setForegroundServiceBehavior(
                NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE  // API 31+
            )
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Disconnect", stopPi)
            .build()
    }

    private fun pushNotificationUpdate() {
        val nm = getSystemService(NotificationManager::class.java)
        nm.notify(NOTIFICATION_ID, buildNotification())
    }

    // ── Stats Loop ────────────────────────────────────────────────────────────

    private fun startStatsLoop() {
        statsJob?.cancel()
        statsJob = serviceScope.launch {
            while (isActive) {
                delay(STATS_INTERVAL_MS)
                withContext(Dispatchers.Main) {
                    pushNotificationUpdate()
                }
            }
        }
    }

    // ── WakeLock ──────────────────────────────────────────────────────────────
    // We use a PARTIAL_WAKE_LOCK so the CPU stays active but the screen can
    // sleep — a full FULL_WAKE_LOCK would drain battery unreasonably.

    private fun acquireWakeLock() {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            WAKELOCK_TAG
        ).also { wl ->
            wl.setReferenceCounted(false)
            wl.acquire(24 * 60 * 60 * 1000L) // Acquire for max 24 hours; released in onDestroy
        }
        Log.d(TAG, "WakeLock acquired")
    }

    private fun releaseWakeLock() {
        wakeLock?.let {
            if (it.isHeld) it.release()
        }
        wakeLock = null
        Log.d(TAG, "WakeLock released")
    }

    // ── Network Change Listener (Wi-Fi ↔ Cellular Auto-Reconnect) ─────────────

    private fun registerNetworkCallback() {
        val request = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .build()

        networkCallback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                Log.d(TAG, "Network available: $network — triggering reconnect check")
                // Broadcast to Dart layer; VpnEngine will reconnect if tunnel dropped.
                VpnPlugin.tunnelFdSink?.success(mapOf("event" to "network_available"))
            }

            override fun onLost(network: Network) {
                Log.d(TAG, "Network lost: $network")
                VpnPlugin.tunnelFdSink?.success(mapOf("event" to "network_lost"))
            }

            override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) {
                val isWifi     = caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)
                val isCellular = caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)
                Log.d(TAG, "Network caps changed — wifi=$isWifi cellular=$isCellular")
                VpnPlugin.tunnelFdSink?.success(
                    mapOf("event" to "network_changed", "wifi" to isWifi, "cellular" to isCellular)
                )
            }
        }

        connectivityManager.registerNetworkCallback(request, networkCallback!!)
    }

    private fun unregisterNetworkCallback() {
        networkCallback?.let {
            connectivityManager.unregisterNetworkCallback(it)
            networkCallback = null
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private fun formatBytes(bytes: Long): String {
        return when {
            bytes >= 1_073_741_824L -> "%.2f GB".format(bytes / 1_073_741_824.0)
            bytes >= 1_048_576L     -> "%.2f MB".format(bytes / 1_048_576.0)
            bytes >= 1024L          -> "%.1f KB".format(bytes / 1024.0)
            else                    -> "$bytes B"
        }
    }
}
