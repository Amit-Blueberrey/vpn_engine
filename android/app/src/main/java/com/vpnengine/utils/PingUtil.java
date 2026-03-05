// android/app/src/main/java/com/vpnengine/utils/PingUtil.java
package com.vpnengine.utils;

import java.net.InetSocketAddress;
import java.net.Socket;

public class PingUtil {
    /**
     * TCP connect ping – measures time to establish TCP connection.
     * Returns milliseconds, or -1 on failure.
     */
    public static int pingHost(String host, int port) {
        long start = System.currentTimeMillis();
        try (Socket socket = new Socket()) {
            socket.connect(new InetSocketAddress(host, port), 3000);
            return (int)(System.currentTimeMillis() - start);
        } catch (Exception e) {
            return -1;
        }
    }
}
