@preconcurrency import ActivityKit
import Foundation
import Observation
import TrackerCore

@MainActor @Observable final class ActivityManager {
  private(set) var current: Activity<JourneyActivityAttributes>?
  private(set) var session: RemoteActivitySession?
  private(set) var message: String?
  var onChange: (() -> Void)?
  private var tokenTask: Task<Void, Never>?
  private var stateTask: Task<Void, Never>?
  #if DEBUG
    private var previewDisabled = false
    func configurePreview(_ scenario: String) {
      previewDisabled = scenario == "activity-off"
      if scenario == "expired" { message = "实时活动已满 8 小时，请回到行程重新开启。" }
    }
  #endif
  var enabled: Bool {
    #if DEBUG
      if previewDisabled { return false }
    #endif
    return ActivityAuthorizationInfo().areActivitiesEnabled
  }
  var journeyID: String? { current?.attributes.journeyID }
  var status: String {
    if !enabled { return "系统未允许实时活动" }
    if current != nil { return "实时活动进行中" }
    return message ?? "尚未开启实时活动"
  }
  func restore() {
    guard
      let activity = Activity<JourneyActivityAttributes>.activities.first(where: {
        $0.activityState == .active || $0.activityState == .stale
      })
    else { return }
    attach(activity)
  }
  func start(_ journey: Journey) async {
    guard enabled else {
      message = "请在系统设置中允许实时活动。"
      return
    }
    guard let state = Projection.state(journey) else { return }
    await end()
    do {
      let activity = try Activity.request(
        attributes: JourneyActivityAttributes(journeyID: journey.id),
        content: ActivityContent(
          state: state, staleDate: Date(timeIntervalSince1970: state.validUntilEpoch)),
        pushType: .token)
      UserDefaults.standard.set(
        Int(Date().timeIntervalSince1970), forKey: "activity-start-\(activity.id)")
      attach(activity)
      message = nil
    } catch { message = "无法开启实时活动：\(error.localizedDescription)" }
  }
  private func attach(_ activity: Activity<JourneyActivityAttributes>) {
    current = activity
    tokenTask?.cancel()
    stateTask?.cancel()
    let started = UserDefaults.standard.integer(forKey: "activity-start-\(activity.id)")
    let startedAt = started > 0 ? started : Int(Date().timeIntervalSince1970)
    func accept(_ data: Data) {
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
        guard let self, !Task.isCancelled else { return }
        if state == .ended || state == .dismissed {
          self.current = nil
          self.session = nil
          self.message = "实时活动已结束，可回到行程续开。"
          self.onChange?()
          return
        }
      }
    }
  }
  func update(_ journey: Journey) async {
    guard let current, current.attributes.journeyID == journey.id,
      let state = Projection.state(journey)
    else { return }
    if journey.completed || journey.trackingEnded {
      await end()
      return
    }
    await current.update(
      ActivityContent(state: state, staleDate: Date(timeIntervalSince1970: state.validUntilEpoch)))
  }
  func end() async {
    tokenTask?.cancel()
    stateTask?.cancel()
    if let current { await current.end(nil, dismissalPolicy: .immediate) }
    current = nil
    session = nil
    onChange?()
  }
}
