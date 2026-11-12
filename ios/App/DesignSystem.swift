import SwiftUI
import TrackerCore

// Tokens from design/source/style.css. Keep fill yellow separate from readable accent text.
enum VIATheme {
  private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
    Color(
      uiColor: UIColor { traits in
        let hex = traits.userInterfaceStyle == .dark ? dark : light
        return UIColor(
          red: CGFloat((hex >> 16) & 255) / 255,
          green: CGFloat((hex >> 8) & 255) / 255,
          blue: CGFloat(hex & 255) / 255, alpha: 1)
      })
  }
  static let yellow = Color(red: 1, green: 0.8, blue: 0)
  static let ink = adaptive(0x252622, 0xf1f0e8)
  static let muted = adaptive(0x6e6e63, 0xaaa99d)
  static let background = adaptive(0xf6f5f0, 0x191917)
  static let surface = adaptive(0xfffefa, 0x262622)
  static let tintSurface = adaptive(0xfff1b8, 0x40371c)
  static let accent = adaptive(0x705600, 0xffcf3f)
  static let line = adaptive(0xe5e4dc, 0x414138)
  static let amber = adaptive(0x94601a, 0xecc381)
  static let amberSurface = adaptive(0xf9edd9, 0x413622)
  static func date(_ date: Date, zone: String = "America/Toronto", format: String = "M月d日 EEEE")
    -> String
  {
    Time.formatted(date, zone: zone, pattern: format)
  }
}
struct VIADivider: View {
  var body: some View { Rectangle().fill(VIATheme.line).frame(height: 1).accessibilityHidden(true) }
}
struct SidebarButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .opacity(configuration.isPressed ? 0.7 : 1)
      .background(configuration.isPressed ? VIATheme.line : .clear,
        in: RoundedRectangle(cornerRadius: 12))
      .contentShape(Rectangle())
  }
}
struct VIACard<Content: View>: View {
  var tinted = false
  var padding: CGFloat = 18
  var spacing: CGFloat = 14
  @ViewBuilder var content: Content
  var body: some View {
    VStack(alignment: .leading, spacing: spacing) { content }
      .padding(padding).frame(maxWidth: .infinity, alignment: .leading)
      .background(
        tinted ? VIATheme.tintSurface : VIATheme.surface, in: RoundedRectangle(cornerRadius: 22))
  }
}
struct StatusPill: View {
  var title: String
  var symbol: String = ""
  var warning = false
  var body: some View {
    HStack(spacing: 5) {
      if !symbol.isEmpty { Image(systemName: symbol).font(.system(size: 11)) }
      Text(title)
    }.font(.system(size: 11, weight: .medium)).padding(.horizontal, 9).padding(.vertical, 5)
      .background(warning ? VIATheme.amberSurface : VIATheme.tintSurface, in: Capsule())
      .foregroundStyle(warning ? VIATheme.amber : VIATheme.accent)
  }
}
struct Notice: View {
  var text: String
  var symbol: String = "info.circle"
  var body: some View {
    Label {
      Text(text).fixedSize(horizontal: false, vertical: true)
    } icon: {
      Image(systemName: symbol)
    }
    .font(.footnote).lineSpacing(4).foregroundStyle(VIATheme.accent)
    .padding(.vertical, 13).padding(.horizontal, 14).frame(maxWidth: .infinity, alignment: .leading)
    .background(VIATheme.tintSurface, in: RoundedRectangle(cornerRadius: 14))
  }
}
struct PrimaryButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var enabled
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.font(.body.weight(.medium))
      .multilineTextAlignment(.center).padding(.horizontal, 14).padding(.vertical, 12)
      .frame(maxWidth: .infinity, minHeight: 50)
      .foregroundStyle(Color(red: 0.145, green: 0.149, blue: 0.133))
      .background(VIATheme.yellow, in: RoundedRectangle(cornerRadius: 15))
      .opacity(!enabled ? 0.4 : configuration.isPressed ? 0.7 : 1)
  }
}
struct SecondaryButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var enabled
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.font(.body.weight(.medium))
      .multilineTextAlignment(.center).padding(.horizontal, 14).padding(.vertical, 12)
      .frame(maxWidth: .infinity, minHeight: 50).foregroundStyle(VIATheme.accent)
      .background(
        VIATheme.tintSurface.opacity(configuration.isPressed ? 0.6 : 1),
        in: RoundedRectangle(cornerRadius: 15))
      .opacity(enabled ? 1 : 0.4)
  }
}
struct VIASectionLabel: View {
  var title: String
  var detail = ""
  var body: some View {
    HStack {
      Text(title).font(.system(size: 13, weight: .semibold))
      Spacer()
      Text(detail).font(.system(size: 11)).foregroundStyle(VIATheme.muted)
    }
  }
}
struct VIANavigationBar<Trailing: View>: View {
  var title: String
  var back = ""
  var onBack: () -> Void = {}
  @ViewBuilder var trailing: Trailing
  var body: some View {
    ZStack {
      Text(title).font(.headline).lineLimit(1).minimumScaleFactor(0.75).padding(.horizontal, 90)
      HStack {
        if !back.isEmpty {
          Button(action: onBack) {
            HStack(spacing: 2) {
              Image(systemName: "chevron.left")
              Text(back)
            }
            .font(.system(size: 15)).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
          }.buttonStyle(.plain).foregroundStyle(VIATheme.accent)
        }
        Spacer()
        trailing.foregroundStyle(VIATheme.accent).frame(minWidth: 44, minHeight: 44)
      }
    }.frame(minHeight: 45).padding(.horizontal, 24).background(VIATheme.background)
      .overlay(alignment: .bottom) { VIADivider() }
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
        Text(state.elapsedTitle)
      } else if frozen || compact {
        Text(Self.duration(Int(state.targetDate.timeIntervalSince(now)), compact: compact))
      } else {
        Text(timerInterval: now...state.targetDate, countsDown: true)
      }
    }.monospacedDigit().accessibilityLabel(
      state.phase == .completed
        ? "行程已完成"
        : now >= state.targetDate
          ? state.elapsedTitle
          : "\(state.countdownLabel)，\(max(0,Int(state.targetDate.timeIntervalSince(now)/60))) 分钟")
  }
  private static func duration(_ seconds: Int, compact: Bool) -> String {
    let h = seconds / 3600
    let m = (seconds % 3600) / 60
    let s = seconds % 60
    if compact {
      if seconds > 0 && seconds < 60 { return "不到 1 分钟" }
      return h > 0 ? "\(h) 小时 \(m) 分" : "\(m) 分钟"
    }
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
  }
}
/// A trip still outside its tracking window shows when it happens, not a running clock.
struct UpcomingSummary: View {
  var journey: Journey
  var now: Date = Date()
  var body: some View {
    let leg = journey.legs.first
    let zone = leg?.boarding?.timeZone ?? "America/Toronto"
    let leave = journey.plannedLeaveAt
    VStack(alignment: .leading, spacing: 0) {
      Text("计划出门").font(.system(size: 12)).foregroundStyle(VIATheme.accent)
      Text(Projection.upcomingDayTitle(leave: leave, now: now, zone: zone))
        .font(.system(size: 53, weight: .regular)).tracking(-2.5).minimumScaleFactor(0.6)
        .lineLimit(1).padding(.vertical, 5)
      Text(
        "\(VIATheme.date(leave, zone: zone, format: "M月d日 EEE")) \(Time.format(leave, zone: zone)) 出门 · \(Time.format(leg?.boarding?.departure?.scheduledDate, zone: zone)) 发车"
      ).font(.system(size: 12)).foregroundStyle(VIATheme.amber)
      Label("出门前 5 小时开始倒计时", systemImage: "clock")
        .font(.system(size: 11)).foregroundStyle(VIATheme.muted).padding(.top, 8)
    }.frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityElement(children: .combine)
  }
}
struct JourneyHero: View {
  var journey: Journey
  var now: Date = Date()
  var frozen = false
  @ScaledMetric(relativeTo: .largeTitle) private var countdownSize: CGFloat = 53
  @Environment(\.dynamicTypeSize) private var typeSize
  @Environment(\.horizontalSizeClass) private var sizeClass
  var body: some View {
    let resolved = Projection.resolvedJourney(journey, now: now)
    if let state = Projection.state(resolved, now: now), let leg = resolved.currentLeg {
      VStack(alignment: .leading, spacing: 0) {
        HStack {
          StatusPill(title: state.phase.title, symbol: state.phase.symbol)
          Spacer()
          Text("VIA \(state.trainNumber) · 第 \(state.currentLegIndex+1) 段")
            .font(.system(size: 10)).foregroundStyle(VIATheme.muted)
        }
        Text(state.countdownLabel).font(.system(size: 12)).foregroundStyle(VIATheme.accent).padding(
          .top, sizeClass == .regular ? 14 : 12)
        CountdownText(state: state, now: now, frozen: frozen, compact: typeSize.isAccessibilitySize)
          .font(.system(size: sizeClass == .regular ? 61 : countdownSize, weight: .regular))
          .tracking(-3)
          .minimumScaleFactor(0.65).lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
          .contentTransition(.numericText()).padding(.top, 7).padding(.bottom, 5)
        let riding = state.phase == .riding || state.phase == .completed
        let event = riding ? leg.alighting?.arrival : leg.boarding?.departure
        let zone = (riding ? leg.alighting?.timeZone : leg.boarding?.timeZone) ?? "America/Toronto"
        HStack {
          Text(
            state.phase == .beforeDeparture
              ? "前往车站需要 \(journey.travelToStationMinutes) 分钟" : delayText(event)
          )
          .foregroundStyle(VIATheme.amber)
          Spacer()
          if state.phase != .beforeDeparture {
            Text("计划 \(Time.format(event?.scheduledDate,zone:zone))").foregroundStyle(
              VIATheme.muted)
          }
        }.font(.system(size: 12))
        if state.phase == .riding {
          GeometryReader { geometry in
            Capsule().fill(VIATheme.yellow.opacity(0.22))
            Capsule().fill(VIATheme.yellow).frame(width: geometry.size.width * state.progress)
          }.frame(height: 4).padding(.top, 12)
          HStack {
            Text(state.origin)
            Spacer()
            Text(state.destination)
          }
          .font(.system(size: 11)).foregroundStyle(VIATheme.muted).padding(.top, 9)
        }
        VIADivider().padding(.top, 11).padding(.bottom, 10)
        HStack {
          Text(
            state.phase == .beforeDeparture
              ? "\(Time.format(journey.plannedLeaveAt,zone:zone)) 出门"
              : "\(state.targetIsEstimate ? "预计" : "计划") \(Time.format(state.targetDate,zone:zone)) \(riding ? "到达" : "发车")"
          )
          Spacer()
          Image(systemName: "arrow.up.right")
        }.font(.system(size: 12))
      }.padding(.vertical, sizeClass == .regular ? 21 : 17).padding(.horizontal, 19)
        .background(VIATheme.tintSurface, in: RoundedRectangle(cornerRadius: 24))
    }
  }
  private func delayText(_ event: EventTime?) -> String {
    guard let s = event?.scheduledDate, let e = event?.estimatedDate else {
      return journey.currentLeg?.source == .reference ? "参考时刻" : "按计划"
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
