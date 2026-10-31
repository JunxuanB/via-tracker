import Network
import CryptoKit
import SwiftData
import SwiftUI
import TrackerCore
import UserNotifications
import WidgetKit

enum AppEnvironment: String, CaseIterable, Sendable {
  case production, test
  var title: String { self == .production ? "正式环境" : "公网测试环境" }
}
struct AppConfiguration: Equatable, Sendable {
  var environment: AppEnvironment
  var baseURL: URL
  var localOnly = false
  var isTest: Bool { environment == .test }
  var remotePush: Bool { !localOnly }
  var namespace: String {
    isTest ? "test-" + SHA256.hash(data: Data(baseURL.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined() : "installation"
  }
  static func configuration(for environment: AppEnvironment) -> Self {
    let key = environment == .test ? "TestAPIBaseURL" : "APIBaseURL"
    let fallback = environment == .test ? "https://via-tracker-test.junxuan-bao.workers.dev" : "https://via-tracker-api.junxuan-bao.workers.dev"
    return Self(environment: environment, baseURL: URL(string: Bundle.main.object(forInfoDictionaryKey: key) as? String ?? fallback)!)
  }
  static var selected: Self {
    if let value = UserDefaults.standard.string(forKey: "selected-environment"), let environment = AppEnvironment(rawValue: value) {
      return configuration(for: environment)
    }
    #if DEBUG
      if let value = ProcessInfo.processInfo.environment["VIA_API_URL"], let url = URL(string: value),
        ["http", "https"].contains(url.scheme ?? ""), url.host != nil, url.user == nil, url.password == nil {
        return Self(environment: .test, baseURL: url, localOnly: true)
      }
    #endif
    return configuration(for: .production)
  }
  func defaultsKey(_ key: String) -> String { isTest ? "\(key).\(namespace)" : key }
}

@Model final class JourneyRecord {
  @Attribute(.unique) var id: String
  var payload: Data
  var revision: Int
  var dirty: Bool
  init(_ journey: Journey) throws {
    id = journey.id
    payload = try JSONEncoder().encode(journey)
    revision = 1
    dirty = true
  }
  var journey: Journey? { try? JSONDecoder().decode(Journey.self, from: payload) }
}
@Model final class FeedRecord {
  @Attribute(.unique) var id: String
  var payload: Data
  init(_ data: Data) {
    id = "feed"
    payload = data
  }
}
@Model final class DeletionRecord {
  @Attribute(.unique) var id: String
  init(_ id: String) { self.id = id }
}

@MainActor @Observable final class AppStore {
  let container: ModelContainer
  let configuration: AppConfiguration
  var changeEnvironment: ((AppEnvironment) async -> Void)?
  var isSwitchingEnvironment = false
  var environmentError: String?
  var testDeviceCode: String?
  private var shuttingDown = false
  private let context: ModelContext
  let activities = ActivityManager()
  let api: APIClient
  var journeys: [Journey] = []
  var trains: [TrainSnapshot] = []
  var feed: TrainEnvelope?
  var isRefreshing = false
  var isStartingActivity = false
  var isOffline = false
  var errorMessage: String?
  var syncError: String?
  var storageError: String?
  var recoveredAt: Date?
  var selectedJourneyID: String?
  var primaryID: String? {
    didSet {
      if qaScenario == nil { UserDefaults.standard.set(primaryID, forKey: configuration.defaultsKey("primary-journey")) }
      publish()
    }
  }
  var notificationStatus = "未检查"
  var diagnostics: String?
  var qaScenario: String? {
    #if DEBUG
      ProcessInfo.processInfo.environment["VIA_QA_SCENARIO"]
    #else
      nil
    #endif
  }
  var qaDate: Date? {
    guard let scenario = qaScenario else { return nil }
    let time =
      switch scenario {
      case "before", "upcoming": "12:55"
      case "onway": "13:42"
      case "waiting": "13:55"
      case "interchange": "18:42"
      case "second-leg": "19:25"
      case "complete": "21:12"
      case "pending-update": "18:43"
      case "crossday": "23:50"
      default: "17:24"
      }
    if scenario == "timezone" { return Time.parse("2026-11-07T04:00:00-08:00") }
    return Time.parse("2026-11-06T\(time):00-05:00")
  }
  var appearance: String {
    didSet { if qaScenario == nil { UserDefaults.standard.set(appearance, forKey: "appearance") } }
  }
  let apiBaseURL: String
  var isTestMode: Bool { configuration.isTest }
  var supportsRemotePush: Bool { configuration.remotePush }
  private var records: [JourneyRecord] = []
  private var syncing = false
  private var syncRequested = false
  private var systemServicesReady = false
  private var activatingServices = false
  private var isForeground = false
  private var lastPublished: SharedSnapshot?
  private var monitor: NWPathMonitor?
  private var loop: Task<Void, Never>?
  private var tokenObserver: NSObjectProtocol?
  var primaryJourney: Journey? {
    if let primaryID, let j = journeys.first(where: { $0.id == primaryID }) { return j }
    return journeys.filter {
      !$0.trackingEnded && Projection.state($0, now: qaDate ?? Date())?.phase != .completed
    }.min {
      abs(($0.legs.first?.planningDeparture ?? 0) - Date().timeIntervalSince1970)
        < abs(($1.legs.first?.planningDeparture ?? 0) - Date().timeIntervalSince1970)
    }
  }
  var sourceMessage: String? {
    if isOffline { return "当前离线，显示上次保存的信息" }
    if let errorMessage { return errorMessage }
    if let feed, feed.sourceStatus != "healthy" { return "暂时无法刷新，已保留上次的信息" }
    if let recoveredAt, Date().timeIntervalSince(recoveredAt) < 15 { return "连接已恢复 · 已获取最新数据" }
    return nil
  }
  nonisolated static func openStorage(configuration selected: AppConfiguration = .selected) throws -> ModelContainer {
    #if DEBUG
      let preview = ProcessInfo.processInfo.environment["VIA_QA_SCENARIO"] != nil
    #else
      let preview = false
    #endif
    var configuration = ModelConfiguration(isStoredInMemoryOnly: preview)
    if !preview, selected.isTest {
      let url = selected.baseURL
      // Test environments never open the user's real journeys or feed cache.
      let folder = URL.applicationSupportDirectory.appendingPathComponent("VIA-Test", isDirectory: true)
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      let key = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
      configuration = ModelConfiguration(url: folder.appendingPathComponent(key + ".store"))
    }
    #if DEBUG
      if preview, let id = ProcessInfo.processInfo.environment["VIA_QA_STORE"],
        UUID(uuidString: id) != nil
      {
        let folder = URL.cachesDirectory.appendingPathComponent("VIA-QA", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        configuration = ModelConfiguration(url: folder.appendingPathComponent(id + ".store"))
      }
    #endif
    #if DEBUG
      if let value = ProcessInfo.processInfo.environment["VIA_QA_STORAGE_DELAY_MS"],
        let milliseconds = Double(value), milliseconds > 0
      {
        Thread.sleep(forTimeInterval: min(milliseconds, 10000) / 1000)
      }
    #endif
    StartupTrace.mark("storage.open.begin")
    let container = try ModelContainer(
      for: JourneyRecord.self, FeedRecord.self, DeletionRecord.self,
      configurations: configuration)
    StartupTrace.mark("storage.open.end")
    return container
  }
  init(container: ModelContainer, configuration: AppConfiguration = .selected) {
    self.configuration = configuration
    self.container = container
    context = ModelContext(container)
    apiBaseURL = configuration.baseURL.absoluteString
    api = APIClient(baseURL: configuration.baseURL, identityNamespace: configuration.namespace)
    appearance = UserDefaults.standard.string(forKey: "appearance") ?? "system"
    primaryID = UserDefaults.standard.string(forKey: configuration.defaultsKey("primary-journey"))
    activities.remotePushEnabled = configuration.remotePush
    activities.testSource = configuration.isTest ? apiBaseURL : nil
    if configuration.remotePush { UserDefaults.standard.set(true, forKey: configuration.defaultsKey("push-token-update-pending")) }
    records = (try? context.fetch(FetchDescriptor<JourneyRecord>())) ?? []
    reloadJourneys()
    if let cached = try? context.fetch(FetchDescriptor<FeedRecord>()).first,
      let value = try? JSONDecoder().decode(TrainEnvelope.self, from: cached.payload)
    {
      feed = value
      trains = value.trains
    }
    StartupTrace.mark("cache.read.end")
    activities.onChange = { [weak self] in
      guard let self else { return }
      for record in self.records {
        record.revision += 1
        record.dirty = true
      }
      self.persist()
      Task { await self.syncPending() }
    }

    #if DEBUG
      if let scenario = qaScenario {
        PreviewScenarios.configure(self, scenario: scenario)
        return
      }
    #endif
    let monitor = NWPathMonitor()
    self.monitor = monitor
    monitor.pathUpdateHandler = { [weak self] path in
      let offline = path.status != .satisfied
      Task { @MainActor [weak self] in
        guard let self else { return }
        let recovered = self.isOffline && !offline
        self.isOffline = offline
        if recovered && self.isForeground {
          await self.refresh()
          if self.errorMessage == nil && self.feed?.sourceStatus == "healthy" {
            self.recoveredAt = Date()
            Task { @MainActor [weak self] in
              try? await Task.sleep(for: .seconds(15))
              self?.recoveredAt = nil
            }
          }
        }
      }
    }
    monitor.start(queue: DispatchQueue(label: "via.network"))
    tokenObserver = NotificationCenter.default.addObserver(
      forName: .viaPushToken, object: nil, queue: .main
    ) { [weak self] note in
      let token = note.object as? String
      Task { @MainActor [weak self] in await self?.registerPushToken(token) }
    }
    // Restore system services only after the root view has appeared.
  }
  func activateSystemServices() async {
    guard qaScenario == nil, !systemServicesReady, !activatingServices else { return }
    activatingServices = true
    defer { activatingServices = false }
    await activities.restore()
    if let id = activities.journeyID {
      if let journey = journeys.first(where: { $0.id == id }), !journey.completed, !journey.trackingEnded {
        primaryID = id
      } else {
        await activities.end()
      }
    }
    systemServicesReady = true
    publish()
    await syncPending()
  }
  private func reloadJourneys() {
    journeys = records.compactMap(\.journey).sorted { $0.createdAt > $1.createdAt }
  }
  @discardableResult
  private func persist() -> Bool {
    do {
      try context.save()
      storageError = nil
      reloadJourneys()
      publish()
      return true
    } catch {
      context.rollback()
      if let saved = try? context.fetch(FetchDescriptor<JourneyRecord>()) { records = saved }
      reloadJourneys()
      storageError = "本地保存失败：\(error.localizedDescription)"
      return false
    }
  }
  @discardableResult
  func save(_ journey: Journey) -> Bool {
    do {
      if let r = records.first(where: { $0.id == journey.id }) {
        r.payload = try JSONEncoder().encode(journey)
        r.revision += 1
        r.dirty = true
      } else {
        let r = try JourneyRecord(journey)
        records.append(r)
        context.insert(r)
      }
      try context.save()
      storageError = nil
      reloadJourneys()
      publish()
      Task {
        if let latest = journeys.first(where: { $0.id == journey.id }) {
          await activities.update(latest)
        }
        await syncPending()
      }
      return true
    } catch {
      context.rollback()
      if let saved = try? context.fetch(FetchDescriptor<JourneyRecord>()) { records = saved }
      reloadJourneys()
      storageError = "本地保存失败：\(error.localizedDescription)"
      return false
    }
  }
  @discardableResult
  func delete(_ journey: Journey) -> Bool {
    guard let r = records.first(where: { $0.id == journey.id }) else { return true }
    do {
      context.delete(r)
      context.insert(DeletionRecord(journey.id))
      try context.save()
      records.removeAll { $0.id == journey.id }
      storageError = nil
      reloadJourneys()
      if primaryID == journey.id { primaryID = nil }
      publish()
      Task {
        if activities.journeyID == journey.id { await activities.end() }
        await syncPending()
      }
      return true
    } catch {
      context.rollback()
      if let saved = try? context.fetch(FetchDescriptor<JourneyRecord>()) { records = saved }
      reloadJourneys()
      storageError = "本地删除失败：\(error.localizedDescription)"
      return false
    }
  }
  func setPrimary(_ journey: Journey) {
    primaryID = journey.id
    Task {
      if primaryID == journey.id, activities.journeyID != nil && activities.journeyID != journey.id {
        await activities.end()
      }
    }
  }
  func startActivity(_ journey: Journey) async {
    guard !isStartingActivity, !activities.isChanging else { return }
    isStartingActivity = true
    defer { isStartingActivity = false }
    await activities.restore()
    var j = journeys.first(where: { $0.id == journey.id }) ?? journey
    j.trackingEnded = false
    guard save(j) else { return }
    primaryID = j.id
    // ActivityManager.start ends the previous activity before requesting the new one.
    await activities.start(j)
  }
  func stopTracking(_ journey: Journey) {
    var j = journey
    j.trackingEnded = true
    save(j)
  }
  private func publish() {
    guard qaScenario == nil, !shuttingDown else { return }
    let snapshot = SharedSnapshot(journey: primaryJourney, apiBaseURL: apiBaseURL, testMode: isTestMode)
    guard snapshot != lastPublished else { return }
    do {
      try snapshot.write()
      lastPublished = snapshot
      WidgetCenter.shared.reloadTimelines(ofKind: "CurrentJourney")
    } catch {
      diagnostics = "小组件摘要尚未保存，将在下次刷新时重试。"
    }
  }
  func foreground(_ active: Bool) {
    guard !active || !shuttingDown else { return }
    isForeground = active
    loop?.cancel()
    guard active else { return }
    loop = Task {
      var failures = 0
      while !Task.isCancelled {
        await refresh()
        let delay: Double
        if errorMessage != nil || feed?.sourceStatus != "healthy" {
          delay = [5.0, 15, 30, 60][min(failures, 3)]
          failures += 1
        } else {
          delay = isTestMode ? 3 : 60
          failures = 0
        }
        do { try await Task.sleep(for: .seconds(delay + Double.random(in: 0...1))) } catch {
          return
        }
      }
    }
  }
  func refresh() async {
    guard qaScenario == nil, !shuttingDown, !isRefreshing else { return }
    isRefreshing = true
    defer { isRefreshing = false }
    do {
      if let value = try await api.trains(), value.snapshotVersion >= (feed?.snapshotVersion ?? 0) {
        let data = try JSONEncoder().encode(value)
        if let cached = try context.fetch(FetchDescriptor<FeedRecord>()).first {
          cached.payload = data
        } else {
          context.insert(FeedRecord(data))
        }
        for r in records {
          if let old = r.journey {
            let j = Projection.reconcile(old, snapshots: value.trains)
            if j != old {
              r.payload = try JSONEncoder().encode(j)
              r.revision += 1
              r.dirty = true
            }
          }
        }
        guard persist() else {
          await api.invalidateTrainCache()
          return
        }
        feed = value
        trains = value.trains
      }
      errorMessage = nil
      await syncPending()
      if let id = activities.journeyID, let journey = journeys.first(where: { $0.id == id }) {
        await activities.update(journey)
      }
    } catch {
      guard !Task.isCancelled else { return }
      errorMessage = "暂时无法更新 · 保留最近有效数据"
      diagnostics = error.localizedDescription
    }
  }
  func syncPending() async {
    guard qaScenario == nil, supportsRemotePush, !shuttingDown, systemServicesReady, !isOffline else { return }
    if syncing {
      syncRequested = true
      return
    }
    syncing = true
    defer { syncing = false }
    repeat {
      syncRequested = false
      do {
        try Task.checkCancellation()
        try await syncOnce()
        syncError = nil
        guard persist() else { return }
      } catch {
        if !Task.isCancelled { syncError = "行程已保存在本机，联网后会继续更新。" }
        persist()
        return
      }
    } while syncRequested && !isOffline && !Task.isCancelled
  }
  private func flushDeletions() async throws {
    let ids = try context.fetch(FetchDescriptor<DeletionRecord>()).map(\.id)
    for id in ids {
      try Task.checkCancellation()
      try await api.delete(id)
      if let deletion = try context.fetch(FetchDescriptor<DeletionRecord>()).first(where: { $0.id == id }) {
        context.delete(deletion)
      }
    }
  }
  private func mergeRemote(_ remote: Journey, into local: Journey) -> Journey {
    // A response can have the same user revision but an older train snapshot.
    var merged = Projection.reconcile(local, snapshots: remote.legs.map(\.snapshot))
    if local.syncChoice == .ask && !local.scheduleChangePrompted && remote.pendingScheduleChange {
      merged.pendingScheduleChange = true
      merged.scheduleChangePrompted = true
    }
    return merged
  }
  private func syncOnce() async throws {
    try await api.register(environment: Self.apnsEnvironment)
    if isTestMode { testDeviceCode = try await api.testDeviceCode() }
    if UserDefaults.standard.bool(forKey: configuration.defaultsKey("push-token-update-pending")) {
      let token = UserDefaults.standard.string(forKey: configuration.defaultsKey("ordinary-push-token"))
      try await api.pushToken(token, environment: Self.apnsEnvironment)
      if UserDefaults.standard.string(forKey: configuration.defaultsKey("ordinary-push-token")) == token {
        UserDefaults.standard.set(false, forKey: configuration.defaultsKey("push-token-update-pending"))
      } else {
        syncRequested = true
      }
    }
    try await flushDeletions()
    // Never hold a SwiftData record across a suspension: it may be deleted by the UI.
    let ids = records.filter(\.dirty).map(\.id)
    for id in ids {
      try Task.checkCancellation()
      guard let record = records.first(where: { $0.id == id }), let journey = record.journey else { continue }
      let revision = record.revision
      if journey.trackingEnded {
        try await api.delete(id)
        if let current = records.first(where: { $0.id == id }), current.revision == revision {
          current.dirty = false
        }
        continue
      }
      let response: SubscriptionResponse
      do {
        response = try await api.sync(SubscriptionRequest(
          journey: journey, revision: revision,
          activity: activities.journeyID == id ? activities.session : nil))
      } catch APIClient.Failure.http(409, _) {
        let values = try await api.subscriptions()
        if let current = records.first(where: { $0.id == id }),
          let server = values.first(where: { $0.id == id }) {
          current.revision = max(current.revision, server.revision) + 1
          current.dirty = true
          syncRequested = true
          continue
        }
        throw APIClient.Failure.message("正在合并订阅版本，将自动重试。")
      }
      guard let current = records.first(where: { $0.id == id }),
        current.revision == revision, let local = current.journey else { continue }
      current.payload = try JSONEncoder().encode(mergeRemote(response.journey, into: local))
      current.dirty = false
    }
    // A deletion made while an upload was in flight wins before this pass finishes.
    try await flushDeletions()
    let values = try await api.subscriptions()
    for value in values {
      if let current = records.first(where: { $0.id == value.id }), !current.dirty,
        value.revision == current.revision, let local = current.journey, !local.trackingEnded {
        current.payload = try JSONEncoder().encode(mergeRemote(value.journey, into: local))
      }
    }
  }
  func enableNotifications() async {
    do {
      let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [
        .alert, .sound, .badge,
      ])
      notificationStatus = allowed ? "已允许" : "未允许"
      if allowed && supportsRemotePush {
        UIApplication.shared.registerForRemoteNotifications()
      } else {
        await registerPushToken(nil)
      }
    } catch { notificationStatus = "无法请求通知权限" }
  }
  func checkNotifications() async {
    let settings = await UNUserNotificationCenter.current().notificationSettings()
    notificationStatus =
      switch settings.authorizationStatus {
      case .authorized, .provisional, .ephemeral: "已允许"
      case .denied: "未允许"
      default: "尚未请求"
      }
    if settings.authorizationStatus == .denied,
      UserDefaults.standard.string(forKey: configuration.defaultsKey("ordinary-push-token")) != nil
    {
      await registerPushToken(nil)
    }
  }
  private func registerPushToken(_ token: String?) async {
    guard qaScenario == nil, supportsRemotePush, !shuttingDown else { return }
    if UserDefaults.standard.string(forKey: configuration.defaultsKey("ordinary-push-token")) == token,
      !UserDefaults.standard.bool(forKey: configuration.defaultsKey("push-token-update-pending")) { return }
    UserDefaults.standard.set(token, forKey: configuration.defaultsKey("ordinary-push-token"))
    UserDefaults.standard.set(true, forKey: configuration.defaultsKey("push-token-update-pending"))
    await syncPending()
  }
  func prepareForEnvironmentSwitch() async {
    shuttingDown = true
    systemServicesReady = false
    foreground(false)
    monitor?.cancel()
    if let tokenObserver { NotificationCenter.default.removeObserver(tokenObserver) }
    tokenObserver = nil
    activities.onChange = nil
    await activities.end()
    for record in records { record.dirty = true; record.revision += 1 }
    persist()
    await api.suspend(journeyIDs: journeys.map(\.id), publicTest: isTestMode && supportsRemotePush,
      remotePush: supportsRemotePush, environment: Self.apnsEnvironment)
    changeEnvironment = nil
  }
  static var apnsEnvironment: String {
    if let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
      let data = try? Data(contentsOf: url), let content = String(data: data, encoding: .isoLatin1),
      let start = content.range(of: "<?xml"), let end = content.range(of: "</plist>"),
      let xml = String(content[start.lowerBound..<end.upperBound]).data(using: .isoLatin1),
      let plist = try? PropertyListSerialization.propertyList(from: xml, format: nil)
        as? [String: Any], let entitlements = plist["Entitlements"] as? [String: Any],
      let env = entitlements["aps-environment"] as? String
    {
      return env == "development" ? "sandbox" : "production"
    }
    return Bundle.main.object(forInfoDictionaryKey: "APNSEnvironment") as? String == "development"
      ? "sandbox" : "production"
  }
}
extension Notification.Name { static let viaPushToken = Notification.Name("viaPushToken") }
