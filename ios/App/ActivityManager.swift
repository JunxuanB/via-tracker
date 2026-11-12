@preconcurrency import ActivityKit
import Foundation
import Observation
import TrackerCore

@MainActor @Observable final class ActivityManager {
  private(set) var current: Activity<JourneyActivityAttributes>?
  private(set) var session: RemoteActivitySession?
  private(set) var message: String?
  private(set) var messageJourneyID: String?
  private(set) var isChanging = false
  var remotePushEnabled = true
  var testSource: String?
  var onChange: (() -> Void)?
  /// App-wide token the server uses to start an activity while the app is not running.
  private(set) var startToken: String?
  var onStartToken: (() -> Void)?
  private var tokenTask: Task<Void, Never>?
  private var stateTask: Task<Void, Never>?
  private var startTokenTask: Task<Void, Never>?
  private var remoteStartTask: Task<Void, Never>?
  private var generation = 0
  #if DEBUG
    private var previewDisabled = false
    func configurePreview(_ scenario: String) {
      previewDisabled = scenario == "activity-off"
      enabled = !previewDisabled
      if scenario == "expired" { message = L10n.text("实时活动已结束，可以重新开启。") }
    }
  #endif
  private(set) var enabled = false
  private(set) var frequentPushesEnabled = false
  func refreshAuthorization() async {
    // ActivityKit may wait for an OS service. Never perform this IPC from View.body.
    let authorization = await Task.detached(priority: .utility) {
      let info = ActivityAuthorizationInfo()
      return (info.areActivitiesEnabled, info.frequentPushesEnabled)
    }.value
    #if DEBUG
      enabled = !previewDisabled && authorization.0
    #else
      enabled = authorization.0
    #endif
    frequentPushesEnabled = authorization.1
  }
  var journeyID: String? { current?.attributes.journeyID }
  var status: String {
    if isChanging { return L10n.text("正在更新实时活动…") }
    if current != nil { return L10n.text("实时活动已开启") }
    if !enabled { return L10n.text("系统未允许实时活动") }
    return message ?? L10n.text("尚未开启实时活动")
  }
  func feedback(for id: String) -> String? {
    messageJourneyID == nil || messageJourneyID == id ? message : nil
  }
  private func report(_ text: String, journeyID: String?) {
    message = text
    messageJourneyID = journeyID
  }
  /// Reconcile on every foreground entry: a swipe can happen while this process is suspended.
  func restore() async {
    guard !isChanging else { return }
    let expectedGeneration = generation
    await refreshAuthorization()
    let existing = await Task.detached(priority: .utility) {
      Activity<JourneyActivityAttributes>.activities
    }.value
    guard generation == expectedGeneration, !isChanging else { return }
    let live = existing.filter {
      $0.attributes.testSource == testSource && ($0.activityState == .active || $0.activityState == .stale)
    }
    if let current, live.contains(where: { $0.id == current.id }) { return }
    if let old = current {
      clearCurrent()
      if old.activityState == .dismissed { await old.end(nil, dismissalPolicy: .immediate) }
      guard generation == expectedGeneration, !isChanging else { return }
      report(L10n.text("实时活动已关闭，点「开启实时活动」即可重新显示。"), journeyID: old.attributes.journeyID)
    }
    // A dismissed card can remain in ActivityKit's registry. End it explicitly
    // before dropping the handle so a subsequent request starts a fresh session.
    for activity in existing where activity.attributes.testSource == testSource
      && activity.activityState == .dismissed {
      await activity.end(nil, dismissalPolicy: .immediate)
    }
    guard generation == expectedGeneration, !isChanging else { return }
    if let activity = live.first { attach(activity) }
  }
  /// The server starts an activity when a saved trip enters its tracking window,
  /// and replaces one that is about to reach the system's eight-hour limit.
  func observeRemoteStarts() {
    if remoteStartTask == nil {
      remoteStartTask = Task { [weak self] in
        for await activity in Activity<JourneyActivityAttributes>.activityUpdates {
          guard !Task.isCancelled, let self else { return }
          await self.adopt(activity)
        }
      }
    }
    guard remotePushEnabled, startTokenTask == nil else { return }
    startTokenTask = Task { [weak self] in
      for await data in Activity<JourneyActivityAttributes>.pushToStartTokenUpdates {
        guard !Task.isCancelled, let self else { return }
        let token = data.map { String(format: "%02x", $0) }.joined()
        if self.startToken != token {
          self.startToken = token
          self.onStartToken?()
        }
      }
    }
  }
  func stopObserving() {
    remoteStartTask?.cancel()
    startTokenTask?.cancel()
    remoteStartTask = nil
    startTokenTask = nil
  }
  private func adopt(_ activity: Activity<JourneyActivityAttributes>) async {
    guard !isChanging, activity.attributes.testSource == testSource, current?.id != activity.id,
      activity.activityState == .active || activity.activityState == .stale else { return }
    let replaced = current
    attach(activity)
    onChange?()
    if let replaced {
      UserDefaults.standard.removeObject(forKey: "activity-start-\(replaced.id)")
      await replaced.end(nil, dismissalPolicy: .immediate)
    }
  }
  func start(_ journey: Journey) async {
    guard !isChanging else { return }
    isChanging = true
    generation += 1
    let operation = generation
    defer { if generation == operation { isChanging = false } }
    report(L10n.text("正在开启…"), journeyID: journey.id)
    await refreshAuthorization()
    guard generation == operation else { return }
    guard enabled else {
      report(L10n.text("系统未允许实时活动，请前往设置开启。"), journeyID: journey.id)
      return
    }
    guard let state = Projection.state(journey), state.phase != .completed else {
      report(L10n.text("已到达目的地，无需再开启实时活动。"), journeyID: journey.id)
      return
    }
    // Clear the old session before requesting a new token, including an activity dismissed outside the app.
    await finishCurrent()
    guard generation == operation else { return }
    let remaining = Activity<JourneyActivityAttributes>.activities.filter {
      $0.attributes.testSource == testSource
    }
    for activity in remaining {
      guard generation == operation else { return }
      await activity.end(nil, dismissalPolicy: .immediate)
    }
    guard generation == operation else { return }
    do {
      let activity = try Activity.request(
        attributes: JourneyActivityAttributes(journeyID: journey.id, testSource: testSource),
        content: ActivityContent(
          state: state, staleDate: Date(timeIntervalSince1970: state.validUntilEpoch)),
        pushType: remotePushEnabled ? .token : nil)
      UserDefaults.standard.set(
        Int(Date().timeIntervalSince1970), forKey: "activity-start-\(activity.id)")
      attach(activity)
      report(L10n.text("已开启，可在锁定屏幕查看行程。"), journeyID: journey.id)
    } catch {
      report(L10n.text("暂时无法开启：%@。请检查系统的实时活动设置后重试。", String(describing: error.localizedDescription)), journeyID: journey.id)
    }
  }
  private func clearCurrent() {
    tokenTask?.cancel()
    stateTask?.cancel()
    if let current { UserDefaults.standard.removeObject(forKey: "activity-start-\(current.id)") }
    let changed = current != nil || session != nil
    current = nil
    session = nil
    if changed { onChange?() }
  }
  private func attach(_ activity: Activity<JourneyActivityAttributes>) {
    current = activity
    session = nil
    tokenTask?.cancel()
    stateTask?.cancel()
    let started = UserDefaults.standard.integer(forKey: "activity-start-\(activity.id)")
    let startedAt = started > 0
      ? started : Int(activity.attributes.startedAt ?? Date().timeIntervalSince1970)
    if started == 0 { UserDefaults.standard.set(startedAt, forKey: "activity-start-\(activity.id)") }
    let source = testSource
    func accept(_ data: Data) {
      guard remotePushEnabled, current?.id == activity.id else { return }
      let token = data.map { String(format: "%02x", $0) }.joined()
      guard session?.id != activity.id || session?.token != token else { return }
      session = RemoteActivitySession(
        id: activity.id, token: token, startedAt: startedAt, revision: (session?.revision ?? 0) + 1,
        testSource: source)
      onChange?()
    }
    if let data = activity.pushToken { accept(data) }
    tokenTask = Task {
      for await data in activity.pushTokenUpdates {
        guard !Task.isCancelled else { return }
        accept(data)
      }
    }
    stateTask = Task { [weak self] in
      for await state in activity.activityStateUpdates {
        guard let self, !Task.isCancelled, self.current?.id == activity.id else { return }
        if state == .ended || state == .dismissed {
          self.clearCurrent()
          if state == .dismissed { await activity.end(nil, dismissalPolicy: .immediate) }
          guard self.current == nil else { return }
          self.report(L10n.text("实时活动已关闭，点「开启实时活动」即可重新显示。"), journeyID: activity.attributes.journeyID)
          return
        }
      }
    }
  }
  func update(_ journey: Journey) async {
    guard !isChanging, let current, current.attributes.journeyID == journey.id,
      let state = Projection.state(journey)
    else { return }
    guard current.activityState == .active || current.activityState == .stale else {
      clearCurrent()
      if current.activityState == .dismissed { await current.end(nil, dismissalPolicy: .immediate) }
      guard self.current == nil else { return }
      report(L10n.text("实时活动已关闭，可以重新开启。"), journeyID: journey.id)
      return
    }
    if state.phase == .completed { await end(finalState: state); return }
    if journey.trackingEnded { await end(); return }
    await current.update(
      ActivityContent(state: state, staleDate: Date(timeIntervalSince1970: state.validUntilEpoch)))
  }
  func end(finalState: TrackerCore.ActivityState? = nil) async {
    generation += 1
    let operation = generation
    isChanging = true
    let id = journeyID
    defer { if generation == operation { isChanging = false } }
    await finishCurrent(finalState: finalState)
    guard generation == operation else { return }
    report(finalState == nil ? L10n.text("实时活动已关闭，行程仍保留。") : L10n.text("已到达，欢迎来到 %@。", String(describing: finalState!.destination)), journeyID: id)
  }
  private func finishCurrent(finalState: TrackerCore.ActivityState? = nil) async {
    let ending = current
    clearCurrent()
    guard let ending else { return }
    if let finalState {
      await ending.end(ActivityContent(state: finalState, staleDate: nil),
        dismissalPolicy: .after(Date().addingTimeInterval(3600)))
    } else {
      await ending.end(nil, dismissalPolicy: .immediate)
    }
  }
}
