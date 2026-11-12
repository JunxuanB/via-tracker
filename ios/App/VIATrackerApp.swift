import OSLog
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
  ) async -> UNNotificationPresentationOptions { [.banner, .sound, .list] }
}
@main struct VIATrackerApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
  init() { StartupTrace.mark("app.init") }
  var body: some Scene {
    WindowGroup { AppBootstrap() }
  }
}

struct AppBootstrap: View {
  @AppStorage(InstallationOnboarding.completionKey) private var onboardingCompleted = false
  @State private var store: AppStore?
  @State private var failure: String?
  @State private var loading = false
  @State private var takingLonger = false
  @State private var pendingURL: URL?
  var body: some View {
    Group {
      if let store {
        if onboardingCompleted || InstallationOnboarding.bypassForPreview {
          RootView(store: store, pendingURL: $pendingURL).id(store.configuration.namespace)
            .onAppear { StartupTrace.mark("root.appear") }
        } else {
          OnboardingView(store: store) { onboardingCompleted = true }
        }
      } else {
        VStack(spacing: 18) {
          Image(systemName: "tram.fill").font(.system(size: 42)).foregroundStyle(VIATheme.accent)
            .frame(width: 90, height: 90).background(
              VIATheme.tintSurface, in: RoundedRectangle(cornerRadius: 24))
          Text("Train Tracker").font(.system(size: 27, weight: .semibold))
          if let failure {
            Text("无法打开本地行程").font(.headline)
            Text(failure).font(.system(size: 13)).multilineTextAlignment(.center).foregroundStyle(
              VIATheme.muted)
            Button("重试") { Task { await load() } }.buttonStyle(PrimaryButtonStyle()).frame(
              maxWidth: 240)
          } else {
            ProgressView().tint(VIATheme.accent)
            Text(takingLonger ? "正在打开本地数据，请稍候…" : "正在载入行程")
              .font(.system(size: 13)).foregroundStyle(VIATheme.muted)
          }
        }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity).viaBackground()
          .onAppear { StartupTrace.mark("bootstrap.appear") }
      }
    }.onOpenURL { pendingURL = $0 }
      .task { await load() }
      .task {
        try? await Task.sleep(for: .seconds(5))
        if store == nil && failure == nil { takingLonger = true }
      }
  }
  @MainActor private func load() async {
    guard store == nil, !loading else { return }
    loading = true
    failure = nil
    defer { loading = false }
    do {
      let configuration = AppConfiguration.selected
      let container = try await Task.detached(priority: .userInitiated) {
        try AppStore.openStorage(configuration: configuration)
      }.value
      guard !Task.isCancelled else { return }
      let next = AppStore(container: container, configuration: configuration)
      next.changeEnvironment = { await switchEnvironment($0) }
      store = next
    } catch { failure = error.localizedDescription }
  }
  @MainActor private func switchEnvironment(_ target: AppEnvironment) async {
    // The test environment exists for development builds only.
    #if !DEBUG
      guard target == .production else { return }
    #endif
    guard let previous = store, !previous.isSwitchingEnvironment,
      target != previous.configuration.environment || previous.configuration.localOnly else { return }
    previous.isSwitchingEnvironment = true
    previous.environmentError = nil
    defer { previous.isSwitchingEnvironment = false }
    do {
      let configuration = AppConfiguration.configuration(for: target)
      if target == .test {
        try await APIClient(baseURL: configuration.baseURL).validatePublicTestEnvironment()
      }
      let container = try await Task.detached(priority: .userInitiated) {
        try AppStore.openStorage(configuration: configuration)
      }.value
      await previous.prepareForEnvironmentSwitch()
      #if DEBUG
        UserDefaults.standard.set(target.rawValue, forKey: "selected-environment")
      #endif
      pendingURL = nil
      let next = AppStore(container: container, configuration: configuration)
      next.changeEnvironment = { await switchEnvironment($0) }
      store = next
    } catch {
      previous.environmentError = "暂时无法切换环境，请检查连接后重试。原有行程仍保留。"
    }
  }
}

// Startup events contain timing and stage names only, never journey or credential data.
enum StartupTrace {
  private static let logger = Logger(subsystem: "com.junxuanb.viatracker", category: "Startup")
  nonisolated static func mark(_ event: String) {
    let uptime = ProcessInfo.processInfo.systemUptime
    logger.notice("\(event, privacy: .public) uptime=\(uptime)")
    #if DEBUG
      FileHandle.standardError.write(Data("VIA_STARTUP \(event) uptime=\(uptime)\n".utf8))
    #endif
  }
}
