import SwiftUI
import TrackerCore
@preconcurrency import WidgetKit

private let viaYellow = Color(red: 1, green: 0.8, blue: 0)
struct ActivitySummary: View {
  var state: TrackerCore.ActivityState
  var stale: Bool
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Label("VIA \(state.trainNumber)", systemImage: state.phase.symbol).font(.caption.bold())
        Spacer()
        Text(stale ? "数据较旧" : state.phase.title).font(.caption).foregroundStyle(.secondary)
      }
      Text("\(state.origin) → \(state.destination)").font(.subheadline).lineLimit(2)
      HStack(alignment: .lastTextBaseline) {
        VStack(alignment: .leading, spacing: 3) {
          Text(state.countdownLabel).font(.caption)
          if state.phase == .completed {
            Text("已到达").font(.title2)
          } else if state.waitingForUpdate || state.targetDate <= Date() {
            Text("等待更新").font(.title2)
          } else {
            Text(timerInterval: Date()...state.targetDate, countsDown: true).font(
              .title.monospacedDigit()
            ).contentTransition(.numericText()).accessibilityLabel(
              "\(state.countdownLabel)，\(Int(state.targetDate.timeIntervalSinceNow/60))分钟")
          }
        }
        Spacer()
        if let next = state.nextTrainNumber {
          VStack(alignment: .trailing) {
            Text("下一段 VIA \(next)")
            if let gap = state.connectionMinutes { Text("间隔 \(gap) 分钟") }
          }.font(.caption)
        }
      }
      if state.phase == .riding { ProgressView(value: state.progress).tint(viaYellow) }
      Text(
        "\(state.reference ? "参考时刻 · ":"")获取于 \(Time.format(Date(timeIntervalSince1970:state.sourceFetchedEpoch)))\(stale ? " · 时间可能已变化":"")"
      ).font(.caption2).foregroundStyle(.secondary)
    }
  }
}
struct JourneyEntry: TimelineEntry {
  var date: Date
  var journey: Journey?
}
struct JourneyWidgetView: View {
  var entry: JourneyEntry
  @Environment(\.widgetFamily) private var systemFamily
  var familyOverride: WidgetFamily? = nil
  private var family: WidgetFamily { familyOverride ?? systemFamily }
  var body: some View {
    Group {
      if let j = entry.journey, let state = Projection.state(j, now: entry.date) {
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Label("VIA \(state.trainNumber)", systemImage: state.phase.symbol).font(.caption.bold())
            Spacer()
            if state.validUntilEpoch < entry.date.timeIntervalSince1970 {
              Image(systemName: "clock.badge.exclamationmark").accessibilityLabel("数据较旧")
            }
          }
          Text("\(state.origin) → \(state.destination)").font(.caption).lineLimit(2)
          HStack {
            VStack(alignment: .leading, spacing: 5) {
              Text(state.countdownLabel).font(.caption)
              if state.phase == .completed {
                Text("已到达").font(.title2)
              } else if state.waitingForUpdate {
                Text("等待更新").font(.title2)
              } else {
                Text(
                  timerInterval: entry.date...max(entry.date, state.targetDate), countsDown: true
                ).font(.title2.monospacedDigit())
              }
            }
            if family == .systemMedium, let next = state.nextTrainNumber {
              Spacer()
              Divider()
              VStack(alignment: .leading) {
                Text("下一段 VIA \(next)").font(.subheadline.bold())
                if let gap = state.connectionMinutes { Text("间隔 \(gap) 分钟").font(.caption) }
              }
            }
          }
          Spacer(minLength: 0)
          Text("获取于 \(Time.format(Date(timeIntervalSince1970:state.sourceFetchedEpoch)))").font(
            .caption2
          ).foregroundStyle(.secondary)
        }.widgetURL(URL(string: "viatracker://journey/\(j.id)"))
      } else {
        VStack(alignment: .leading, spacing: 10) {
          Label("VIA Tracker", systemImage: "tram.fill").font(.headline)
          Text("添加行程后，在这里查看乘车时间。").font(.caption).foregroundStyle(.secondary)
        }.widgetURL(URL(string: "viatracker://journey/current"))
      }
    }
  }
}
