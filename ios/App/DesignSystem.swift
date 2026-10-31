import SwiftUI
import TrackerCore

enum VIATheme {
  static let yellow = Color(red: 1, green: 0.8, blue: 0)
  static let ink = Color(
    uiColor: UIColor { traits in
      traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.95, green: 0.95, blue: 0.91, alpha: 1)
        : UIColor(red: 0.145, green: 0.149, blue: 0.133, alpha: 1)
    })
  static let background = Color(
    uiColor: UIColor { traits in
      traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.098, green: 0.098, blue: 0.09, alpha: 1)
        : UIColor(red: 0.965, green: 0.961, blue: 0.941, alpha: 1)
    })
  static let surface = Color(
    uiColor: UIColor { traits in
      traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.149, green: 0.149, blue: 0.133, alpha: 1)
        : UIColor(red: 1, green: 0.996, blue: 0.98, alpha: 1)
    })
  static let tintSurface = Color(
    uiColor: UIColor { traits in
      traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.25, green: 0.216, blue: 0.11, alpha: 1)
        : UIColor(red: 1, green: 0.945, blue: 0.72, alpha: 1)
    })
  static let accent = Color(
    uiColor: UIColor { traits in
      traits.userInterfaceStyle == .dark
        ? UIColor(red: 1, green: 0.81, blue: 0.25, alpha: 1)
        : UIColor(red: 0.44, green: 0.337, blue: 0, alpha: 1)
    })
}
struct VIACard<Content: View>: View {
  var tinted = false
  @ViewBuilder var content: Content
  var body: some View {
    VStack(alignment: .leading, spacing: 16) { content }.padding(22).frame(
      maxWidth: .infinity, alignment: .leading
    ).background(
      tinted ? VIATheme.tintSurface : VIATheme.surface, in: RoundedRectangle(cornerRadius: 24))
  }
}
struct StatusPill: View {
  var title: String
  var symbol: String = "antenna.radiowaves.left.and.right"
  var body: some View {
    Label(title, systemImage: symbol).font(.caption.weight(.medium)).padding(.horizontal, 11)
      .padding(.vertical, 7).background(VIATheme.yellow.opacity(0.18), in: Capsule())
      .foregroundStyle(VIATheme.accent)
  }
}
struct Notice: View {
  var text: String
  var symbol: String = "info.circle"
  var body: some View {
    Label {
      textView
    } icon: {
      Image(systemName: symbol)
    }.font(.subheadline).foregroundStyle(.secondary).padding(16).frame(
      maxWidth: .infinity, alignment: .leading
    ).background(VIATheme.surface, in: RoundedRectangle(cornerRadius: 16))
  }
  private var textView: some View { Text(text).fixedSize(horizontal: false, vertical: true) }
}
struct PrimaryButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.font(.headline).frame(maxWidth: .infinity, minHeight: 52).foregroundStyle(
      Color(red: 0.145, green: 0.149, blue: 0.133)
    ).background(
      VIATheme.yellow.opacity(configuration.isPressed ? 0.7 : 1),
      in: RoundedRectangle(cornerRadius: 16))
  }
}
struct CountdownText: View {
  var state: ActivityState
  var now: Date = Date()
  var frozen = false
  var compact = false
  var body: some View {
    Group {
      if state.phase == .completed {
        Text("已到达")
      } else if now >= state.targetDate || state.waitingForUpdate {
        Text("等待更新")
      } else if frozen || compact {
        Text(Self.duration(Int(state.targetDate.timeIntervalSince(now)), compact: compact))
      } else {
        Text(timerInterval: now...state.targetDate, countsDown: true)
      }
    }.monospacedDigit().accessibilityLabel(
      state.phase == .completed
        ? "行程已完成"
        : now >= state.targetDate
          ? "预计时刻已过，等待更新"
          : "\(state.countdownLabel)，\(max(0,Int(state.targetDate.timeIntervalSince(now)/60))) 分钟")
  }
  private static func duration(_ seconds: Int, compact: Bool) -> String {
    let h = seconds / 3600
    let m = (seconds % 3600) / 60
    let s = seconds % 60
    if compact { return h > 0 ? "\(h) 小时 \(m) 分" : "\(m) 分钟" }
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
  }
}
struct JourneyHero: View {
  var journey: Journey
  var now: Date = Date()
  var frozen = false
  @ScaledMetric(relativeTo: .largeTitle) private var countdownSize: CGFloat = 56
  @Environment(\.dynamicTypeSize) private var typeSize
  var body: some View {
    if let state = Projection.state(journey, now: now), let leg = journey.currentLeg {
      VIACard(tinted: true) {
        (typeSize.isAccessibilitySize
          ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout())) {
            Label(state.phase.title, systemImage: state.phase.symbol)
            if !typeSize.isAccessibilitySize { Spacer() }
            Text("VIA \(state.trainNumber) · 第 \(state.currentLegIndex+1) 段").foregroundStyle(
              .secondary)
          }.font(.caption)
        Text(state.countdownLabel).font(.subheadline).foregroundStyle(VIATheme.accent)
        CountdownText(state: state, now: now, frozen: frozen, compact: typeSize.isAccessibilitySize)
          .font(
            typeSize.isAccessibilitySize
              ? .largeTitle : .system(size: countdownSize, weight: .regular, design: .rounded)
          ).fixedSize(horizontal: false, vertical: true).contentTransition(.numericText()).frame(
            maxWidth: .infinity, alignment: .leading)
        let event = state.phase == .riding ? leg.alighting?.arrival : leg.boarding?.departure
        HStack {
          Text(delayText(event)).foregroundStyle(VIATheme.accent)
          Spacer()
          Text(
            "计划 \(Time.format(event?.scheduledDate,zone:(state.phase == .riding ? leg.alighting?.timeZone : leg.boarding?.timeZone) ?? "America/Toronto"))"
          ).foregroundStyle(.secondary)
        }.font(.caption)
        if state.phase == .riding {
          ProgressView(value: state.progress).tint(VIATheme.yellow)
          HStack {
            Text(state.origin)
            Spacer()
            Text(state.destination)
          }.font(.caption).foregroundStyle(.secondary)
        }
        Divider()
        if state.phase == .beforeDeparture {
          Text(
            "\(Time.format(journey.plannedLeaveAt,zone:leg.boarding?.timeZone ?? "America/Toronto")) 出门 · 前往车站 \(journey.travelToStationMinutes) 分钟"
          ).font(.subheadline)
        } else {
          Text(
            "\(state.phase == .riding ? (state.targetIsEstimate ? "预计到达" : "计划到达") : "发车时刻") \(Time.format(state.targetDate,zone:(state.phase == .riding ? leg.alighting?.timeZone : leg.boarding?.timeZone) ?? "America/Toronto",date:true))"
          ).font(.subheadline)
        }
      }
    }
  }
  private func delayText(_ event: EventTime?) -> String {
    guard let s = event?.scheduledDate, let e = event?.estimatedDate else {
      return journey.currentLeg?.source == .reference ? "参考时刻 · 待同步" : "按计划"
    }
    let minutes = Int(e.timeIntervalSince(s) / 60)
    return minutes > 0 ? "晚点 \(minutes) 分钟" : minutes < 0 ? "预计提前 \(-minutes) 分钟" : "按计划"
  }
}
extension View {
  func viaBackground() -> some View {
    self.background(VIATheme.background).foregroundStyle(VIATheme.ink).tint(VIATheme.accent)
  }
}
