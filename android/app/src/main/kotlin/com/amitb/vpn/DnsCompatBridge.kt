package com.amitb.vpn

import android.os.Build
import android.net.VpnService
import android.util.Log

/**
 * DnsCompatBridge.kt
 *
 * Module 3: Cross-Version Android DNS Compatibility.
 *
 * Android 10+ (API 29+): addDnsServer() is robust and supports
 *   per-app DNS routing + DNS-over-HTTPS bypass.
 *
 * Android 8/9 (API 26-28): addDnsServer() works but requires explicit
 *   route for the DNS server IP to prevent DNS leaks when split tunneling.
 *
 * Android 7 (API 24-25): Has a known bug where DNS isn't captured by the
 *   VPN interface unless the DNS server is in the VPN's routing table.
 *   We add an explicit /32 route for the DNS server to force-route DNS.
 *
 * Call applyCompatibleDns() instead of addDnsServer() directly.
 */
object DnsCompatBridge {

    private const val TAG = "DnsCompatBridge"

    /**
     * Apply DNS settings to the VpnService.Builder in a version-safe way.
     *
     * @param builder   The VpnService.Builder being configured.
     * @param dnsServer The DNS server IP address string (e.g. "1.1.1.1").
     */
    fun applyCompatibleDns(builder: VpnService.Builder, dnsServer: String) {
        Log.d(TAG, "Configuring DNS for API ${Build.VERSION.SDK_INT}: $dnsServer")

        when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q -> {
                // API 29+ (Android 10+): Simply add DNS server.
                // The system properly captures DNS queries and routes them
                // through the VPN tunnel without additional routing rules.
                builder.addDnsServer(dnsServer)
                Log.d(TAG, "API 29+: DNS added directly")
            }

            Build.VERSION.SDK_INT >= Build.VERSION_CODES.O -> {
                // API 26-28 (Android 8/9): Add DNS server AND explicit route
                // for the DNS server IP to ensure DNS traffic enters the tunnel.
                builder.addDnsServer(dnsServer)
                try {
                    builder.addRoute(dnsServer, 32) // /32: route only DNS IP
                    Log.d(TAG, "API 26-28: DNS + /32 route added")
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to add DNS route: ${e.message}")
                }
            }

            Build.VERSION.SDK_INT >= Build.VERSION_CODES.N -> {
                // API 24-25 (Android 7): Bug workaround — add both a /32
                // host route AND add it as DNS server. Also set MTU to 1280
                // to avoid fragmentation bugs present on Android 7.x.
                try {
                    builder.addDnsServer(dnsServer)
                    builder.addRoute(dnsServer, 32)
                    builder.setMtu(1280) // Safer MTU for Android 7
                    Log.d(TAG, "API 24-25: DNS + /32 route + MTU 1280 applied")
                } catch (e: Exception) {
                    Log.w(TAG, "Legacy DNS compat error: ${e.message}")
                    // Last resort: add DNS without route
                    try { builder.addDnsServer(dnsServer) } catch (_: Exception) {}
                }
            }

            else -> {
                // Below API 24: Not supported. Log and skip.
                Log.e(TAG, "API ${Build.VERSION.SDK_INT} is below minimum (24). DNS not configured.")
            }
        }
    }

    /**
     * Returns true if the running OS version is fully supported.
     */
    fun isSupported(): Boolean = Build.VERSION.SDK_INT >= Build.VERSION_CODES.N
}
