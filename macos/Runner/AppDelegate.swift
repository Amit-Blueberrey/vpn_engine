// ios/Runner/AppDelegate.swift
import UIKit
import Flutter

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {

    private var methodChannelHandler: VpnMethodChannelHandler?
    private var eventChannelHandler: VpnEventChannelHandler?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        guard let controller = window?.rootViewController as? FlutterViewController else {
            fatalError("rootViewController is not FlutterViewController")
        }

        let binaryMessenger = controller.binaryMessenger

        // Register method channel
        methodChannelHandler = VpnMethodChannelHandler(binaryMessenger: binaryMessenger)
        methodChannelHandler?.register()

        // Register event channels
        eventChannelHandler = VpnEventChannelHandler(binaryMessenger: binaryMessenger)
        eventChannelHandler?.register()

        GeneratedPluginRegistrant.register(with: self)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}
