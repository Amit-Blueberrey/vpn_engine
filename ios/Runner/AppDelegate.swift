import UIKit
import Flutter

@main
@objc class AppDelegate: FlutterAppDelegate {

  private var methodHandler: VpnMethodChannelHandler?
  private var eventHandler: VpnEventChannelHandler?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    guard let controller = window?.rootViewController as? FlutterViewController else {
      return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    methodHandler = VpnMethodChannelHandler(messenger: controller.binaryMessenger)
    eventHandler  = VpnEventChannelHandler(messenger: controller.binaryMessenger)

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
