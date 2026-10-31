import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    return true
  }
  func application(
    _ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    NotificationCenter.default.post(
      name: .viaPushToken, object: deviceToken.map { String(format: "%02x", $0) }.joined())
  }
  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
  ) async {
    let id = response.notification.request.content.userInfo["journeyID"] as? String
    if let id, let url = URL(string: "viatracker://journey/\(id)") {
      await MainActor.run { UIApplication.shared.open(url) }
    }
  }
  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions { [.banner, .sound] }
}
@main struct VIATrackerApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
  @State private var store: AppStore?
  @State private var failure: String?
  init() {
    do { _store = State(initialValue: try AppStore()) } catch {
      _failure = State(initialValue: error.localizedDescription)
    }
  }
  var body: some Scene {
    WindowGroup {
      if let store {
        RootView(store: store)
      } else {
        ContentUnavailableView(
          "无法打开本地行程", systemImage: "externaldrive.badge.exclamationmark",
          description: Text(failure ?? "请重新打开 App。"))
      }
    }
  }
}
