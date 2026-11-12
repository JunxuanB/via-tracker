import ActivityKit
import SwiftUI
import TrackerCore
@preconcurrency import WidgetKit

private let viaYellow = Color(red: 1, green: 0.8, blue: 0)
@main struct VIATrackerWidgets: WidgetBundle {
  var body: some Widget {
    JourneyLiveActivity()
    CurrentJourneyWidget()
  }
}
struct JourneyLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: JourneyActivityAttributes.self) { context in
      ActivitySummary(state: context.state, stale: context.isStale, testMode: context.attributes.testSource != nil).padding(16)
        .activityBackgroundTint(Color(uiColor: .secondarySystemBackground))
        .activitySystemActionForegroundColor(.primary).widgetURL(
          URL(string: "viatracker://journey/\(context.attributes.journeyID)"))
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          IslandTrainLabel(state: context.state)
        }
        DynamicIslandExpandedRegion(.trailing) {
          IslandStatusLabel(state: context.state, stale: context.isStale,
            testMode: context.attributes.testSource != nil)
        }
        DynamicIslandExpandedRegion(.bottom) {
          IslandExpandedContent(state: context.state, stale: context.isStale)
        }
      } compactLeading: {
        Image(systemName: context.state.phase.symbol).foregroundStyle(viaYellow)
      } compactTrailing: {
        IslandCompactTime(state: context.state)
      } minimal: {
        Image(systemName: context.state.phase.symbol).foregroundStyle(viaYellow)
      }
      .widgetURL(URL(string: "viatracker://journey/\(context.attributes.journeyID)"))
      .keylineTint(viaYellow)
    }
  }
}
struct JourneyProvider: TimelineProvider {
  func placeholder(in context: Context) -> JourneyEntry { JourneyEntry(date: Date(), journey: nil) }
  func getSnapshot(in context: Context, completion: @escaping (JourneyEntry) -> Void) {
    let cache = SharedSnapshot.read()
    completion(JourneyEntry(date: Date(), journey: cache?.journey, testMode: cache?.testMode == true))
  }
  func getTimeline(
    in context: Context, completion: @escaping @Sendable (Timeline<JourneyEntry>) -> Void
  ) {
    let cache = SharedSnapshot.read()
    Task {
      var snapshots: [TrainSnapshot] = []
      if let cache, cache.journey != nil, let url = URL(string: "/v1/trains", relativeTo: URL(string: cache.apiBaseURL)),
        let (data, response) = try? await URLSession.shared.data(
          for: URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)),
        (response as? HTTPURLResponse)?.statusCode == 200,
        let envelope = try? JSONDecoder().decode(TrainEnvelope.self, from: data), envelope.schemaVersion == 1 {
        snapshots = envelope.trains
      }
      let now = Date()
      // Never let a request restore a deleted journey, old edits, or the previous environment.
      let latest = SharedSnapshot.read()
      var journey = latest?.journey
      if let saved = SharedSnapshot.read(widgetCache: true), saved.apiBaseURL == latest?.apiBaseURL,
        let cachedJourney = saved.journey, let selected = journey, selected.id == cachedJourney.id {
        journey = Projection.reconcile(selected, snapshots: cachedJourney.legs.map(\.snapshot))
      }
      if latest?.apiBaseURL == cache?.apiBaseURL, let current = journey {
        journey = Projection.reconcile(current, snapshots: snapshots)
        if var refreshed = latest, !snapshots.isEmpty {
          refreshed.journey = journey
          try? refreshed.write(widgetCache: true)
        }
      }
      var dates = [now]
      if let journey {
        dates += Projection.timelineDates(journey)
        if let state = Projection.state(journey) {
          dates.append(Date(timeIntervalSince1970: state.validUntilEpoch))
        }
        if let arrival = journey.legs.last?.alighting?.arrival?.effectiveDate {
          dates.append(arrival.addingTimeInterval(86400))
        }
      }
      if let until = latest?.visibleUntil { dates.append(until) }
      dates = dates.filter { $0 >= now && $0 <= now.addingTimeInterval(7 * 86400) }
      let refresh = latest?.testMode == true ? 300.0 : 900.0
      completion(Timeline(entries: Array(Set(dates)).sorted().map { date in
        var visible = journey
        if let j = visible, Projection.state(j, now: date)?.phase == .completed {
          let until = latest?.visibleUntil ?? j.legs.last?.alighting?.arrival?.effectiveDate?.addingTimeInterval(86400)
          if let until, date >= until { visible = nil }
        }
        return JourneyEntry(date: date, journey: visible, testMode: latest?.testMode == true)
      }, policy: .after(now.addingTimeInterval(refresh))))
    }
  }
}
struct CurrentJourneyWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "CurrentJourney", provider: JourneyProvider()) { entry in
      JourneyWidgetView(entry: entry).containerBackground(for: .widget) {
        Color(uiColor: .secondarySystemBackground)
      }
    }.pushHandler(JourneyWidgetPushHandler.self).configurationDisplayName(L10n.text("当前行程")).description(L10n.text("查看当前车段、倒计时和同站换乘。")).supportedFamilies([
      .systemSmall, .systemMedium,
    ])
  }
}

struct JourneyWidgetPushHandler: WidgetPushHandler {
  func pushTokenDidChange(_ pushInfo: WidgetPushInfo, widgets: [WidgetInfo]) {
    guard widgets.contains(where: { $0.kind == "CurrentJourney" }),
      let registration = WidgetRegistration.read() else { return }
    Task { await registration.register(pushInfo.token) }
  }
}
