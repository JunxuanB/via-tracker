import SwiftUI
import TrackerCore
@preconcurrency import WidgetKit

private let viaYellow = Color(red: 1, green: 0.8, blue: 0)

extension TrackerCore.ActivityState {
  var compactCountdownLabel: String {
    switch phase {
    case .beforeDeparture: L10n.text("距计划出门")
    case .onTheWay: L10n.text("距发车")
    case .waiting: targetIsEstimate ? L10n.text("预计发车") : L10n.text("计划发车")
    case .riding: targetIsEstimate ? L10n.text("预计到达") : L10n.text("计划到达")
    case .transferring: L10n.text("下一段发车")
    case .completed: L10n.text("已到达")
    }
  }
  var connectionSummary: String? {
    guard let minutes = connectionMinutes else { return nil }
    if minutes < 0 { return L10n.text("到达晚于发车 %@ 分钟", String(describing: minutes.magnitude)) }
    if minutes == 0 { return L10n.text("到发时间重叠") }
    return L10n.text("换乘间隔 %@ 分钟", String(describing: minutes))
  }
  var displayProgress: Double {
    phase == .completed ? 1 : progress.isFinite ? min(1, max(0, progress)) : 0
  }
}

/// A native timer keeps ticking without asking ActivityKit to render every second.
struct ActivityCountdown: View {
  var state: TrackerCore.ActivityState
  var body: some View {
    let now = Date()
    Group {
      if state.phase == .completed {
        Text(L10n.text("已到达"))
      } else if state.waitingForUpdate || state.targetDate <= now {
        Text(state.elapsedTitle)
      } else {
        // Use the same instant for the check and range to avoid a reversed range at departure.
        Text(timerInterval: now...state.targetDate, countsDown: true).monospacedDigit()
      }
    }.lineLimit(1).minimumScaleFactor(0.7)
  }
}

struct IslandTrainLabel: View {
  var state: TrackerCore.ActivityState
  var body: some View {
    Label("VIA \(state.trainNumber)", systemImage: state.phase.symbol)
      .font(.system(size: 13, weight: .semibold)).foregroundStyle(viaYellow)
      .lineLimit(1).minimumScaleFactor(0.8)
  }
}

struct IslandStatusLabel: View {
  var state: TrackerCore.ActivityState
  var stale: Bool
  var testMode = false
  var body: some View {
    HStack(spacing: 4) {
      if testMode { Text(L10n.text("测试")).foregroundStyle(.orange) }
      if stale {
        Image(systemName: "clock.badge.exclamationmark").foregroundStyle(.orange)
          .accessibilityLabel(L10n.text("时刻可能已变化"))
      }
      Text(state.phase == .completed ? L10n.text("已到达") : state.phase.title)
    }.font(.system(size: 11, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
  }
}

/// The expanded island has a much smaller height budget than the lock-screen card.
/// Keep the route and timer to two lines, with progress before optional connection details.
struct IslandExpandedContent: View {
  var state: TrackerCore.ActivityState
  var stale: Bool
  private var arriving: Bool { state.phase == .riding || state.phase == .completed }
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .center, spacing: 12) {
        VStack(alignment: .leading, spacing: 3) {
          Text(arriving ? state.destination : state.origin)
            .font(.system(size: 17, weight: .semibold)).minimumScaleFactor(0.8)
          Text(arriving ? L10n.text("从 %@ 出发", String(describing: state.origin)) : L10n.text("开往 %@", String(describing: state.destination)))
            .font(.system(size: 11)).foregroundStyle(.secondary)
        }.lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(arriving
            ? L10n.text("%@ %@，从 %@ 出发", String(describing: state.phase == .completed ? L10n.text("已到达") : L10n.text("目的站")), String(describing: state.destination), String(describing: state.origin))
            : L10n.text("在 %@ 乘车，开往 %@", String(describing: state.origin), String(describing: state.destination)))
        VStack(alignment: .trailing, spacing: 2) {
          Text(state.phase == .completed ? L10n.text("旅途愉快") : state.compactCountdownLabel)
            .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
          ActivityCountdown(state: state).font(.system(size: 24, weight: .medium))
            .multilineTextAlignment(.trailing)
        }.frame(width: 112, alignment: .trailing)
      }
      if arriving {
        JourneyTimeProgress(state: state)
      }
      if let next = state.nextTrainNumber, state.phase != .completed {
        Text(L10n.text("下一段 VIA %@%@", String(describing: next), String(describing: state.connectionSummary.map { " · \($0)" } ?? "")))
          .font(.system(size: 10)).foregroundStyle(.secondary)
          .lineLimit(1).minimumScaleFactor(0.85)
          .accessibilityLabel(L10n.text("下一段 VIA %@，%@", String(describing: next), String(describing: state.connectionSummary ?? "")))
      } else if stale || state.reference {
        Text(stale ? L10n.text("时刻可能已变化") : L10n.text("按计划时刻"))
          .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
      }
    }.padding(.top, 4)
  }
}

struct IslandCompactTime: View {
  var state: TrackerCore.ActivityState
  var body: some View {
    Group {
      if state.phase == .completed {
        Image(systemName: "checkmark").accessibilityLabel(L10n.text("已到达"))
      } else {
        ActivityCountdown(state: state).font(.system(size: 12, weight: .medium))
          .frame(width: 56, alignment: .trailing).multilineTextAlignment(.trailing)
      }
    }
  }
}

struct ActivitySummary: View {
  var state: TrackerCore.ActivityState
  var stale: Bool
  var testMode = false
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        if testMode { Text(L10n.text("测试")).font(.caption2.bold()).foregroundStyle(.orange) }
        Label("VIA \(state.trainNumber)", systemImage: state.phase.symbol).font(.caption.bold())
        Spacer()
        Text(state.phase.title).font(.caption).foregroundStyle(.secondary)
      }
      Text("\(state.origin) → \(state.destination)").font(.subheadline).lineLimit(2)
      HStack(alignment: .lastTextBaseline) {
        VStack(alignment: .leading, spacing: 3) {
          Text(state.compactCountdownLabel).font(.caption)
          ActivityCountdown(state: state).font(
            state.phase == .completed || state.waitingForUpdate || state.targetDate <= Date()
              ? .title2 : .title.monospacedDigit())
        }
        Spacer()
        if let next = state.nextTrainNumber {
          VStack(alignment: .trailing) {
            Text(L10n.text("下一段 VIA %@", String(describing: next)))
            if let summary = state.connectionSummary { Text(summary) }
          }.font(.caption).multilineTextAlignment(.trailing).lineLimit(2).minimumScaleFactor(0.85)
        }
      }
      if state.phase == .riding { JourneyTimeProgress(state: state) }
      Text(
        L10n.text("%@获取于 %@%@", String(describing: state.reference ? L10n.text("参考时刻 · "):""), String(describing: Time.format(Date(timeIntervalSince1970:state.sourceFetchedEpoch))), String(describing: stale ? L10n.text(" · 时间可能已变化"):""))
      ).font(.caption2).foregroundStyle(.secondary)
    }
  }
}
struct JourneyTimeProgress: View {
  var state: TrackerCore.ActivityState
  var body: some View {
    Group {
      if state.phase == .riding, let start = state.progressStartEpoch, start < state.targetEpoch {
        ProgressView(timerInterval: Date(timeIntervalSince1970: start)...state.targetDate,
          countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
      } else { ProgressView(value: state.displayProgress) }
    }.progressViewStyle(.linear).tint(viaYellow).accessibilityLabel(L10n.text("行程时间进度"))
  }
}
struct JourneyEntry: TimelineEntry {
  var date: Date
  var journey: Journey?
  var testMode = false
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
            if entry.testMode { Text(L10n.text("测试")).font(.caption2.bold()).foregroundStyle(.orange) }
            Label("VIA \(state.trainNumber)", systemImage: state.phase.symbol).font(.caption.bold())
            Spacer()
            if state.validUntilEpoch < entry.date.timeIntervalSince1970 {
              Image(systemName: "clock.badge.exclamationmark").accessibilityLabel(L10n.text("数据较旧"))
            }
          }
          Text("\(state.origin) → \(state.destination)").font(.caption).lineLimit(2)
          HStack {
            VStack(alignment: .leading, spacing: 5) {
              if Projection.isUpcoming(j, now: entry.date) {
                // Days away: a date reads better than a 70-hour timer.
                let zone = j.legs.first?.boarding?.timeZone ?? "America/Toronto"
                Text(L10n.text("%@ 出门", String(describing: Time.format(j.plannedLeaveAt, zone: zone, date: true)))).font(.caption)
                Text(Projection.upcomingDayTitle(leave: j.plannedLeaveAt, now: entry.date, zone: zone))
                  .font(.title2)
              } else if state.phase == .completed {
                Text(state.countdownLabel).font(.caption)
                Text(L10n.text("已到达")).font(.title2)
              } else if state.waitingForUpdate {
                Text(state.countdownLabel).font(.caption)
                Text(state.elapsedTitle).font(.title2)
              } else {
                Text(state.countdownLabel).font(.caption)
                Text(
                  timerInterval: entry.date...max(entry.date, state.targetDate), countsDown: true
                ).font(.title2.monospacedDigit())
              }
            }
            if family == .systemMedium, let next = state.nextTrainNumber {
              Spacer()
              Divider()
              VStack(alignment: .leading) {
                Text(L10n.text("下一段 VIA %@", String(describing: next))).font(.subheadline.bold())
                if let summary = state.connectionSummary { Text(summary).font(.caption) }
              }
            }
          }
          if state.phase == .riding { JourneyTimeProgress(state: state) }
          Spacer(minLength: 0)
          Text(L10n.text("获取于 %@", String(describing: Time.format(Date(timeIntervalSince1970:state.sourceFetchedEpoch))))).font(
            .caption2
          ).foregroundStyle(.secondary)
        }.widgetURL(URL(string: "viatracker://journey/\(j.id)"))
      } else {
        VStack(alignment: .leading, spacing: 10) {
          Label("Train Tracker", systemImage: "tram.fill").font(.headline)
          Text(L10n.text("添加行程后，在这里查看乘车时间。")).font(.caption).foregroundStyle(.secondary)
        }.widgetURL(URL(string: "viatracker://journeys"))
      }
    }
  }
}
