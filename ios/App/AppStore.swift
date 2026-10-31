import Network
import SwiftData
import SwiftUI
import TrackerCore
import UserNotifications
import WidgetKit

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
  private let context: ModelContext
  let activities = ActivityManager()
  let api: APIClient
  var journeys: [Journey] = []
  var trains: [TrainSnapshot] = []
  var feed: TrainEnvelope?
  var isRefreshing = false
  var isOffline = false
  var errorMessage: String?
  var syncError: String?
  var storageError: String?
  var recoveredAt: Date?
  var selectedJourneyID: String?
  var primaryID: String? {
    didSet {
      if qaScenario == nil { UserDefaults.standard.set(primaryID, forKey: "primary-journey") }
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
  private var records: [JourneyRecord] = []
  private var syncing = false
  private var monitor: NWPathMonitor?
  private var loop: Task<Void, Never>?
  private var tokenObserver: NSObjectProtocol?
  var primaryJourney: Journey? {
    if let primaryID, let j = journeys.first(where: { $0.id == primaryID }) { return j }
    return journeys.filter { !$0.completed && !$0.trackingEnded }.min {
      abs(($0.legs.first?.planningDeparture ?? 0) - Date().timeIntervalSince1970)
        < abs(($1.legs.first?.planningDeparture ?? 0) - Date().timeIntervalSince1970)
    }
  }
  var sourceMessage: String? {
    if isOffline { return "设备已断网 · 按最近数据显示" }
    if let errorMessage { return errorMessage }
    if let feed, feed.sourceStatus != "healthy" { return "服务暂时无法更新 · 保留最近有效数据" }
    if let recoveredAt, Date().timeIntervalSince(recoveredAt) < 15 { return "连接已恢复 · 已获取最新数据" }
    return nil
  }
  init() throws {
    #if DEBUG
      let preview = ProcessInfo.processInfo.environment["VIA_QA_SCENARIO"] != nil
    #else
      let preview = false
    #endif
    var configuration = ModelConfiguration(isStoredInMemoryOnly: preview)
    #if DEBUG
      if preview, let id = ProcessInfo.processInfo.environment["VIA_QA_STORE"],
        UUID(uuidString: id) != nil
      {
        let folder = URL.cachesDirectory.appendingPathComponent("VIA-QA", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        configuration = ModelConfiguration(url: folder.appendingPathComponent(id + ".store"))
      }
    #endif
    container = try ModelContainer(
      for: JourneyRecord.self, FeedRecord.self, DeletionRecord.self,
      configurations: configuration)
    context = ModelContext(container)
    apiBaseURL =
      ProcessInfo.processInfo.environment["VIA_API_URL"] ?? Bundle.main.object(
        forInfoDictionaryKey: "APIBaseURL") as? String
      ?? "https://via-tracker-api.junxuan-bao.workers.dev"
    api = APIClient(baseURL: URL(string: apiBaseURL)!)
    appearance = UserDefaults.standard.string(forKey: "appearance") ?? "system"
    primaryID = UserDefaults.standard.string(forKey: "primary-journey")
    records = (try? context.fetch(FetchDescriptor<JourneyRecord>())) ?? []
    reloadJourneys()
    if let cached = try? context.fetch(FetchDescriptor<FeedRecord>()).first,
      let value = try? JSONDecoder().decode(TrainEnvelope.self, from: cached.payload)
    {
      feed = value
      trains = value.trains
    }
    activities.onChange = { [weak self] in
      guard let self else { return }
      for j in self.journeys { self.touch(j.id) }
      Task { await self.syncPending() }
    }
    if !preview { activities.restore() }
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
        if recovered {
          await self.refresh()
          if self.errorMessage == nil {
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
    publish()
  }
  private func reloadJourneys() {
    journeys = records.compactMap(\.journey).sorted { $0.createdAt > $1.createdAt }
  }
  private func persist() {
    do {
      try context.save()
      storageError = nil
    } catch { storageError = "本地保存失败：\(error.localizedDescription)" }
    reloadJourneys()
    publish()
  }
  private func touch(_ id: String) {
    if let r = records.first(where: { $0.id == id }) {
      r.revision += 1
      r.dirty = true
    }
    persist()
  }
  func save(_ journey: Journey) {
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
      persist()
      Task {
        await activities.update(journey)
        await syncPending()
      }
    } catch { storageError = error.localizedDescription }
  }
  func delete(_ journey: Journey) {
    if let r = records.first(where: { $0.id == journey.id }) {
      context.delete(r)
      records.removeAll { $0.id == r.id }
      context.insert(DeletionRecord(journey.id))
      if primaryID == journey.id { primaryID = nil }
      persist()
      Task {
        if activities.journeyID == journey.id { await activities.end() }
        await syncPending()
      }
    }
  }
  func setPrimary(_ journey: Journey) {
    primaryID = journey.id
    Task {
      if activities.journeyID != nil && activities.journeyID != journey.id {
        await activities.end()
      }
    }
  }
  func startActivity(_ journey: Journey) async {
    setPrimary(journey)
    var j = journey
    j.trackingEnded = false
    save(j)
    await activities.start(j)
  }
  func stopTracking(_ journey: Journey) {
    var j = journey
    j.trackingEnded = true
    save(j)
  }
  private func publish() {
    guard qaScenario == nil else { return }
    try? SharedSnapshot(journey: primaryJourney, apiBaseURL: apiBaseURL).write()
    WidgetCenter.shared.reloadAllTimelines()
  }
  func foreground(_ active: Bool) {
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
          delay = 60
          failures = 0
        }
        do { try await Task.sleep(for: .seconds(delay + Double.random(in: 0...1))) } catch {
          return
        }
      }
    }
  }
  func refresh() async {
    guard qaScenario == nil, !isRefreshing else { return }
    isRefreshing = true
    defer { isRefreshing = false }
    do {
      if let value = try await api.trains(), value.snapshotVersion >= (feed?.snapshotVersion ?? 0) {
        feed = value
        trains = value.trains
        let data = try JSONEncoder().encode(value)
        if let cached = try context.fetch(FetchDescriptor<FeedRecord>()).first {
          cached.payload = data
        } else {
          context.insert(FeedRecord(data))
        }
        for r in records {
          if let old = r.journey {
            let j = Projection.reconcile(old, snapshots: trains)
            if j != old {
              r.payload = try JSONEncoder().encode(j)
              r.revision += 1
              r.dirty = true
            }
          }
        }
        persist()
      }
      errorMessage = nil
      await syncPending()
      if let j = primaryJourney { await activities.update(j) }
    } catch {
      guard !Task.isCancelled else { return }
      errorMessage = "暂时无法更新 · 保留最近有效数据"
      diagnostics = error.localizedDescription
    }
  }
  func syncPending() async {
    guard qaScenario == nil, !syncing, !isOffline else { return }
    syncing = true
    defer { syncing = false }
    do {
      try await api.register(environment: Self.apnsEnvironment)
      if UserDefaults.standard.bool(forKey: "push-token-update-pending") {
        try await api.pushToken(
          UserDefaults.standard.string(forKey: "ordinary-push-token"),
          environment: Self.apnsEnvironment)
        UserDefaults.standard.set(false, forKey: "push-token-update-pending")
      }
      for deletion in try context.fetch(FetchDescriptor<DeletionRecord>()) {
        try await api.delete(deletion.id)
        context.delete(deletion)
      }
      for r in records where r.dirty {
        guard let j = r.journey else { continue }
        let revision = r.revision
        if j.trackingEnded {
          try await api.delete(j.id)
          if r.revision == revision { r.dirty = false }
          continue
        }
        let response: SubscriptionResponse
        do {
          response = try await api.sync(
            SubscriptionRequest(
              journey: j, revision: revision,
              activity: activities.journeyID == j.id ? activities.session : nil))
        } catch APIClient.Failure.http(409, _) {
          if let server = try await api.subscriptions().first(where: { $0.id == j.id }) {
            r.revision = max(r.revision, server.revision) + 1
            r.dirty = true
          }
          throw APIClient.Failure.message("正在合并较新的订阅版本，将自动重试。")
        }
        if r.revision == revision {
          r.payload = try JSONEncoder().encode(response.journey)
          r.dirty = false
        }
      }
      let values = try await api.subscriptions()
      for value in values {
        if let r = records.first(where: { $0.id == value.id }), !r.dirty,
          value.revision == r.revision
        {
          r.payload = try JSONEncoder().encode(value.journey)
        }
      }
      syncError = nil
      persist()
    } catch {
      syncError = "后台订阅尚未同步，将在联网后重试。"
      persist()
    }
  }
  func enableNotifications() async {
    do {
      let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [
        .alert, .sound, .badge,
      ])
      notificationStatus = allowed ? "已允许" : "未允许"
      if allowed {
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
      UserDefaults.standard.string(forKey: "ordinary-push-token") != nil
    {
      await registerPushToken(nil)
    }
  }
  private func registerPushToken(_ token: String?) async {
    guard qaScenario == nil else { return }
    UserDefaults.standard.set(token, forKey: "ordinary-push-token")
    UserDefaults.standard.set(true, forKey: "push-token-update-pending")
    await syncPending()
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
