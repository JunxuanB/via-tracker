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
  private var tokenTask: Task<Void, Never>?
  private var stateTask: Task<Void, Never>?
  private var generation = 0
  #if DEBUG
    private var previewDisabled = false
    func configurePreview(_ scenario: String) {
      previewDisabled = scenario == "activity-off"
      enabled = !previewDisabled
      if scenario == "expired" { message = "实时活动已结束，可以重新开启。" }
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
    if isChanging { return "正在更新实时活动…" }
    if current != nil { return "实时活动已开启" }
    if !enabled { return "系统未允许实时活动" }
    return message ?? "尚未开启实时活动"
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
      report("实时活动已关闭，点「开启实时活动」即可重新显示。", journeyID: old.attributes.journeyID)
    }
    if let activity = live.first { attach(activity) }
  }
  func start(_ journey: Journey) async {
    guard !isChanging else { return }
    isChanging = true
    generation += 1
    let operation = generation
    defer { if generation == operation { isChanging = false } }
    report("正在开启…", journeyID: journey.id)
    await refreshAuthorization()
    guard generation == operation else { return }
    guard enabled else {
      report("系统未允许实时活动，请前往设置开启。", journeyID: journey.id)
      return
    }
    guard let state = Projection.state(journey), state.phase != .completed else {
      report("已到达目的地，无需再开启实时活动。", journeyID: journey.id)
      return
    }
    // Clear the old session before requesting a new token, including an activity dismissed outside the app.
    await finishCurrent()
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
      report("已开启，可在锁定屏幕查看行程。", journeyID: journey.id)
    } catch {
      report("暂时无法开启，请稍后重试；也可检查系统的实时活动设置。", journeyID: journey.id)
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
    let startedAt = started > 0 ? started : Int(Date().timeIntervalSince1970)
    func accept(_ data: Data) {
      guard remotePushEnabled, current?.id == activity.id else { return }
      let token = data.map { String(format: "%02x", $0) }.joined()
      guard session?.id != activity.id || session?.token != token else { return }
      session = RemoteActivitySession(
        id: activity.id, token: token, startedAt: startedAt, revision: (session?.revision ?? 0) + 1)
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
          self.report("实时活动已关闭，点「开启实时活动」即可重新显示。", journeyID: activity.attributes.journeyID)
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
      report("实时活动已关闭，可以重新开启。", journeyID: journey.id)
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
    report(finalState == nil ? "实时活动已关闭，行程仍保留。" : "已到达，欢迎来到 \(finalState!.destination)。", journeyID: id)
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
