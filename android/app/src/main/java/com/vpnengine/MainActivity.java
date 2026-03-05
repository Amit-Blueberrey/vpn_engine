// android/app/src/main/java/com/vpnengine/MainActivity.java
package com.vpnengine;

import android.os.Bundle;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import com.vpnengine.channel.VpnMethodChannelHandler;
import com.vpnengine.channel.VpnEventChannelHandler;

public class MainActivity extends FlutterActivity {

    private VpnMethodChannelHandler methodHandler;
    private VpnEventChannelHandler eventHandler;

    @Override
    public void configureFlutterEngine(FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);

        // Register all platform channels
        methodHandler = new VpnMethodChannelHandler(this, flutterEngine);
        methodHandler.register();

        eventHandler = new VpnEventChannelHandler(this, flutterEngine);
        eventHandler.register();
    }

    @Override
    protected void onDestroy() {
        if (methodHandler != null) methodHandler.cleanup();
        if (eventHandler != null) eventHandler.cleanup();
        super.onDestroy();
    }
}
