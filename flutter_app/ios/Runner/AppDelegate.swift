import Flutter
import UIKit
import UserNotifications
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
      AnalyticsStorage.register(with: registry.registrar(forPlugin: "PersonasAnalyticsStorage")!)
    }
    WorkmanagerPlugin.registerPeriodicTask(withIdentifier: "co.local.personas.analytics.sync", earliestBeginInSeconds: NSNumber(value: 15 * 60))
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    AnalyticsStorage.register(with: engineBridge.pluginRegistry.registrar(forPlugin: "PersonasAnalyticsStorage")!)
    PhotosBridge.register(with: engineBridge.pluginRegistry.registrar(forPlugin: "PersonasPhotos")!)
  }
  override func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                              withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    completionHandler(notification.request.identifier.hasPrefix("personas.analysis.") ? [] : [.banner, .sound])
  }

  override func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                              withCompletionHandler completionHandler: @escaping () -> Void) {
    if response.notification.request.identifier.hasPrefix("personas.analysis.") {
      UserDefaults.standard.set(true, forKey: "PersonasOpenAnalysis")
      NotificationCenter.default.post(name: Notification.Name("PersonasOpenAnalysis"), object: nil)
    }
    completionHandler()
  }
}

// Analytics storage is independent of PhotosBridge and excludes the complete
// SQLite directory (database, WAL and SHM) from iCloud/device backups.
final class AnalyticsStorage: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    registrar.addMethodCallDelegate(AnalyticsStorage(), channel: FlutterMethodChannel(name: "co.local.personas/analytics-storage", binaryMessenger: registrar.messenger()))
  }
  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "path" else { result(FlutterMethodNotImplemented); return }
    do {
      var directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("OptionalAnalytics", isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      var values = URLResourceValues(); values.isExcludedFromBackup = true
      try directory.setResourceValues(values)
      result(directory.appendingPathComponent("personas_analytics.db").path)
    } catch {
      result(FlutterError(code: "storage_unavailable", message: "Analítica no disponible", details: nil))
    }
  }
}
