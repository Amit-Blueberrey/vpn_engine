# WireGuard VPN Engine ProGuard Rules
-keep class com.vpnengine.** { *; }
-keep class com.wireguard.** { *; }
-keepclassmembers class * {
    native <methods>;
}
