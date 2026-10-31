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
      ActivitySummary(state: context.state, stale: context.isStale).padding(16)
        .activityBackgroundTint(Color(uiColor: .secondarySystemBackground))
        .activitySystemActionForegroundColor(.primary).widgetURL(
          URL(string: "viatracker://journey/\(context.attributes.journeyID)"))
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Label("VIA \(context.state.trainNumber)", systemImage: context.state.phase.symbol).font(
            .headline
          ).foregroundStyle(viaYellow)
        }
        DynamicIslandExpandedRegion(.trailing) { Text(context.state.phase.title).font(.caption) }
        DynamicIslandExpandedRegion(.bottom) {
          ActivitySummary(state: context.state, stale: context.isStale).padding(.top, 6)
        }
      } compactLeading: {
        Image(systemName: context.state.phase.symbol).foregroundStyle(viaYellow)
      } compactTrailing: {
        compactTime(context.state)
      } minimal: {
        Image(systemName: context.state.phase.symbol).foregroundStyle(viaYellow)
      }
      .widgetURL(URL(string: "viatracker://journey/\(context.attributes.journeyID)"))
      .keylineTint(viaYellow)
    }
  }
  @ViewBuilder private func compactTime(_ state: TrackerCore.ActivityState) -> some View {
    if state.phase == .completed {
      Image(systemName: "checkmark")
    } else if state.waitingForUpdate || state.targetDate <= Date() {
      Text("待更新").font(.caption)
    } else {
      Text(timerInterval: Date()...state.targetDate, countsDown: true).monospacedDigit().font(
        .caption
      ).frame(maxWidth: 70)
    }
  }
}
struct JourneyProvider: TimelineProvider {
  func placeholder(in context: Context) -> JourneyEntry { JourneyEntry(date: Date(), journey: nil) }
  func getSnapshot(in context: Context, completion: @escaping (JourneyEntry) -> Void) {
    completion(JourneyEntry(date: Date(), journey: SharedSnapshot.read()?.journey))
  }
  func getTimeline(
    in context: Context, completion: @escaping @Sendable (Timeline<JourneyEntry>) -> Void
  ) {
    let cache = SharedSnapshot.read()
    Task {
      var journey = cache?.journey
      if let cache, let url = URL(string: "/v1/trains", relativeTo: URL(string: cache.apiBaseURL)),
        let (data, response) = try? await URLSession.shared.data(
          for: URLRequest(url: url, timeoutInterval: 12)),
        (response as? HTTPURLResponse)?.statusCode == 200,
        let envelope = try? JSONDecoder().decode(TrainEnvelope.self, from: data),
        envelope.schemaVersion == 1, let old = journey
      {
        journey = Projection.reconcile(old, snapshots: envelope.trains)
      }
      let now = Date()
      var dates = [now]
      if let journey, let state = Projection.state(journey) {
        dates += [
          journey.plannedLeaveAt, Date(timeIntervalSince1970: state.scheduledEpoch - 900),
          state.targetDate, Date(timeIntervalSince1970: state.validUntilEpoch),
        ].filter { $0 > now && $0 < now.addingTimeInterval(86400) }
      }
      completion(
        Timeline(
          entries: dates.sorted().map { JourneyEntry(date: $0, journey: journey) },
          policy: .after(now.addingTimeInterval(900))))
    }
  }
}
struct CurrentJourneyWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "CurrentJourney", provider: JourneyProvider()) { entry in
      JourneyWidgetView(entry: entry).containerBackground(for: .widget) {
        Color(uiColor: .secondarySystemBackground)
      }
    }.configurationDisplayName("当前行程").description("查看当前车段、倒计时和同站换乘。").supportedFamilies([
      .systemSmall, .systemMedium,
    ])
  }
}
