// android/app/src/main/java/com/vpnengine/model/WgConfig.java
package com.vpnengine.model;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * Android-side WireGuard config model.
 * Mirrors the Flutter VpnConfig, received via MethodChannel as a Map.
 */
public class WgConfig {
    public String tunnelName;
    public String privateKey;
    public String address;
    public String addressV6;
    public List<String> dnsServers = new ArrayList<>();
    public int mtu = 1420;
    public String serverPublicKey;
    public String presharedKey;
    public String serverEndpoint;
    public List<String> allowedIPs = new ArrayList<>();
    public Integer persistentKeepalive;

    @SuppressWarnings("unchecked")
    public static WgConfig fromMap(Map<String, Object> map) {
        WgConfig c = new WgConfig();
        c.tunnelName          = (String) map.get("tunnelName");
        c.privateKey          = (String) map.get("privateKey");
        c.address             = (String) map.get("address");
        c.addressV6           = (String) map.get("addressV6");
        c.serverPublicKey     = (String) map.get("serverPublicKey");
        c.presharedKey        = (String) map.get("presharedKey");
        c.serverEndpoint      = (String) map.get("serverEndpoint");
        c.persistentKeepalive = (Integer) map.get("persistentKeepalive");
        if (map.get("mtu") instanceof Integer) c.mtu = (int) map.get("mtu");
        if (map.get("dnsServers") instanceof List)
            c.dnsServers = (List<String>) map.get("dnsServers");
        if (map.get("allowedIPs") instanceof List)
            c.allowedIPs = (List<String>) map.get("allowedIPs");
        return c;
    }

    public static WgConfig fromJson(JSONObject json) throws Exception {
        WgConfig c = new WgConfig();
        c.tunnelName      = json.optString("tunnelName", "VPNEngine");
        c.privateKey      = json.optString("privateKey");
        c.address         = json.optString("address");
        c.addressV6       = json.optString("addressV6");
        c.serverPublicKey = json.optString("serverPublicKey");
        c.presharedKey    = json.optString("presharedKey");
        c.serverEndpoint  = json.optString("serverEndpoint");
        c.mtu             = json.optInt("mtu", 1420);
        c.persistentKeepalive = json.optInt("persistentKeepalive", 25);
        JSONArray dns = json.optJSONArray("dnsServers");
        if (dns != null) for (int i = 0; i < dns.length(); i++) c.dnsServers.add(dns.getString(i));
        JSONArray ips = json.optJSONArray("allowedIPs");
        if (ips != null) for (int i = 0; i < ips.length(); i++) c.allowedIPs.add(ips.getString(i));
        return c;
    }

    public String toJson() {
        try {
            JSONObject j = new JSONObject();
            j.put("tunnelName",          tunnelName);
            j.put("privateKey",          privateKey);
            j.put("address",             address);
            j.put("addressV6",           addressV6 != null ? addressV6 : "");
            j.put("serverPublicKey",     serverPublicKey);
            j.put("presharedKey",        presharedKey != null ? presharedKey : "");
            j.put("serverEndpoint",      serverEndpoint);
            j.put("mtu",                 mtu);
            j.put("persistentKeepalive", persistentKeepalive != null ? persistentKeepalive : 25);
            JSONArray dns = new JSONArray(dnsServers);
            j.put("dnsServers", dns);
            JSONArray ips = new JSONArray(allowedIPs);
            j.put("allowedIPs", ips);
            return j.toString();
        } catch (Exception e) {
            return "{}";
        }
    }
}
