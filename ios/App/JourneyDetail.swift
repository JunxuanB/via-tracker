import MapKit
import SwiftUI
import TrackerCore

struct JourneyDetail: View {
  @Bindable var store: AppStore
  var id: String
  var showsBackButton = false
  @Environment(\.horizontalSizeClass) private var sizeClass
  @Environment(\.dismiss) private var dismiss
  @Environment(\.dynamicTypeSize) private var typeSize
  @State private var editing = false
  @State private var correcting = false
  @State private var ending = false
  @State private var deleting = false
  @State private var activityActionPending = false
  @State private var contentWidth: CGFloat = 0
  private var journey: Journey? {
    store.journeys.first { $0.id == id }.map { Projection.resolvedJourney($0, now: store.qaDate ?? Date()) }
  }
  var body: some View {
    TimelineView(.periodic(from: .now, by: 15)) { context in
      detail(now: store.qaDate ?? context.date)
    }
  }
  private func detail(now: Date) -> some View {
    Group {
      if let j = journey {
        ScrollView {
          VStack(alignment: .leading, spacing: 12) {
            (typeSize.isAccessibilitySize
              ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
              : AnyLayout(HStackLayout(alignment: .top))) {
                VStack(alignment: .leading, spacing: 6) {
                  Text(detailTitle(j, now: now)).font(.system(size: 20, weight: .semibold))
                  Text(
                    VIATheme.date(
                      j.legs.first?.boarding?.departure?.scheduledDate ?? Date(), format: L10n.text("M月d日 EEE")
                    ) + (j.legs.count > 1 ? L10n.text(" · %@ 段列车", String(describing: j.legs.count)) : "")
                  ).font(.system(size: 12)).foregroundStyle(VIATheme.muted)
                }
                if !typeSize.isAccessibilitySize { Spacer() }
                StatusPill(
                  title: dataStatus(j, now: now),
                  symbol: store.isOffline ? "wifi.slash" : "antenna.radiowaves.left.and.right")
              }
            if let message = store.sourceMessage {
              Notice(text: message, symbol: store.isOffline ? "wifi.slash" : "wifi.exclamationmark")
            }
            if !j.completed, let fetched = j.currentLeg.flatMap({ Time.parse($0.snapshot.sourceFetchedAt) }),
              now.timeIntervalSince(fetched) > 600
            {
              Notice(text: L10n.text("暂时没有新的列车信息，先显示上次的时刻。"), symbol: "clock.badge.exclamationmark")
            }
            if j.pendingScheduleChange {
              VIACard(tinted: true) {
                Text(L10n.text("发车时间有变化")).font(.headline)
                Text(L10n.text("要根据新的发车时间调整出门安排吗？")).font(.subheadline)
                Button(L10n.text("跟随列车时间")) {
                  var changed = store.journeys.first(where: { $0.id == id }) ?? j
                  changed.chooseSync(true)
                  store.save(changed)
                }.buttonStyle(PrimaryButtonStyle())
                Button(L10n.text("保持我的出门安排")) {
                  var changed = store.journeys.first(where: { $0.id == id }) ?? j
                  changed.chooseSync(false)
                  store.save(changed)
                }.frame(minHeight: 44)
              }
            }
            if j.completed {
              VIACard(tinted: true) {
                Label(L10n.text("行程已完成"), systemImage: "checkmark.circle.fill").font(
                  .system(size: 20, weight: .semibold))
                Text(L10n.text("欢迎来到 %@", String(describing: j.legs.last?.alighting?.name ?? L10n.text("目的站")))).font(.system(size: 24))
              }
            }
            if j.currentLeg?.source == .reference { Notice(text: L10n.text("暂未查到这一天的班次，先用参考时刻安排。")) }
            if store.isTestMode && j.manualPhase != nil && !j.completed {
              VIACard(tinted: true) {
                Text(L10n.text("当前使用手动设置的行程状态")).font(.subheadline)
                Button(L10n.text("恢复自动更新")) {
                  guard var saved = store.journeys.first(where: { $0.id == id }) else { return }
                  saved.manualPhase = nil
                  store.save(saved)
                }.frame(minHeight: 44)
              }
            }
            let phase = Projection.state(j, now: now)?.phase
            if phase == .completed {
              VIACard {
                Text(j.displayTitle).font(.system(size: 24, weight: .semibold))
                VIADivider()
                Text(L10n.text("行程已保存在本机")).font(.system(size: 12)).foregroundStyle(VIATheme.muted)
              }
            } else if phase != .riding {
              phaseSteps(phase)
              passengerControls(j, phase: phase)
              hero(j, now: now)
              phaseInformation(j, phase: phase)
              timeline(j, now: now)
              connections(j, now: now)
              map(j)
            } else {
              if sizeClass == .regular && contentWidth >= 800 {
                HStack(alignment: .top, spacing: 24) {
                  VStack(spacing: 20) {
                    hero(j, now: now)
                    map(j)
                  }.frame(maxWidth: .infinity)
                  VStack(spacing: 20) {
                    timeline(j, now: now)
                    connections(j, now: now)
                  }.frame(maxWidth: .infinity)
                }
              } else {
                hero(j, now: now)
                timeline(j, now: now)
                connections(j, now: now)
                map(j)
              }
            }
            if let leg = j.currentLeg {
              ForEach(Array(leg.snapshot.alerts.enumerated()), id: \.offset) { _, alert in
                VIACard {
                  Text(alert.title).font(.headline)
                  Text(alert.body).font(.subheadline)
                  if let value = alert.url, let url = URL(string: value),
                    ["https", "http"].contains(url.scheme ?? "")
                  {
                    Link(L10n.text("查看原始通知"), destination: url)
                  }
                }
              }
            }
            controls(j, now: now).padding(.top, 12)
            DisclosureGroup(L10n.text("更新信息")) {
              if let leg = j.currentLeg {
                Text(L10n.text("上次更新 %@", String(describing: Time.format(Time.parse(leg.snapshot.sourceFetchedAt), date: true))))
              }
              Text(L10n.text("行程会按最新预计时间自动前进；没有预计时间时使用计划时间。"))
              if let error = store.syncError { Text(error) }
            }.font(.caption).foregroundStyle(VIATheme.muted)
          }.padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 20).frame(maxWidth: 1200)
            .frame(maxWidth: .infinity)
        }.refreshable { await store.refresh() }
          .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { contentWidth = $0 }
      } else {
        ContentUnavailableView(L10n.text("行程不存在"), systemImage: "tram")
      }
    }
    .viaBackground().toolbar(.hidden, for: .navigationBar)
    .safeAreaInset(edge: .top, spacing: 0) {
      VIANavigationBar(
        title: L10n.text("行程详情"), back: showsBackButton ? L10n.text("行程") : "", onBack: { dismiss() }
      ) {
        Menu {
          Button(L10n.text("编辑行程"), systemImage: "slider.horizontal.3") { editing = true }
          if store.isTestMode {
            Button(L10n.text("更正行程状态"), systemImage: "hand.tap") { correcting = true }
          }
          if let j = journey, !j.completed, !j.trackingEnded {
            Button(L10n.text("设为主行程"), systemImage: "location.fill") { store.setPrimary(j) }
          }
          Button(L10n.text("结束追踪"), systemImage: "stop.circle", role: .destructive) { ending = true }
          Button(L10n.text("删除行程"), systemImage: "trash", role: .destructive) { deleting = true }
        } label: {
          Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44)
        }.accessibilityLabel(L10n.text("管理行程")).disabled(journey == nil)
      }
    }
    .sheet(isPresented: $editing) {
      if let saved = store.journeys.first(where: { $0.id == id }) {
        AddJourneyFlow(store: store, initialJourney: saved)
      }
    }
    .task {
      if store.isTestMode && store.qaScenario == "correct-stage" { correcting = true }
      if store.qaScenario == "end-confirm" { ending = true }
    }
    .confirmationDialog(L10n.text("更正行程状态"), isPresented: $correcting, titleVisibility: .visible) {
      if store.isTestMode, let j = journey {
        ForEach(Phase.allCases.filter { $0 != .transferring || j.currentLegIndex > 0 }, id: \.self)
        { phase in
          Button(phase.title) {
            var changed = j
            changed.manualPhase = phase
            changed.completed = phase == .completed
            store.save(changed)
          }
        }
        Button(L10n.text("按列车时间自动更新")) {
          var changed = j
          changed.manualPhase = nil
          changed.completed = false
          store.save(changed)
        }
      }
    }
    .confirmationDialog(L10n.text("结束追踪？"), isPresented: $ending, titleVisibility: .visible) {
      Button(L10n.text("结束追踪"), role: .destructive) { if let journey { store.stopTracking(journey) } }
    } message: {
      Text(L10n.text("实时活动会结束，行程仍保存在本机。"))
    }
    .confirmationDialog(L10n.text("删除本机行程？"), isPresented: $deleting, titleVisibility: .visible) {
      Button(L10n.text("删除行程"), role: .destructive) {
        if let journey, store.delete(journey) { dismiss() }
      }
    } message: {
      Text(L10n.text("此操作会移除行程并取消后台订阅。"))
    }
  }
  private func dataStatus(_ j: Journey, now: Date) -> String {
    if j.completed { return L10n.text("已完成") }
    if j.trackingEnded { return L10n.text("已结束追踪") }
    if j.currentLeg?.source == .reference { return L10n.text("参考时刻") }
    if store.isOffline { return L10n.text("离线") }
    guard let fetched = j.currentLeg.flatMap({ Time.parse($0.snapshot.sourceFetchedAt) }),
      now.timeIntervalSince(fetched) <= 600, store.feed?.sourceStatus == "healthy",
      store.errorMessage == nil else { return L10n.text("最近数据") }
    return L10n.text("实时")
  }
  private func detailTitle(_ j: Journey, now: Date) -> String {
    let phase = Projection.state(j, now: now)?.phase
    let station = j.currentLeg?.boarding?.name ?? ""
    if phase == .completed { return L10n.text("已到达") }
    if phase == .onTheWay { return L10n.text("前往 %@ 车站", String(describing: station)) }
    if phase == .waiting { return L10n.text("在 %@ 候车", String(describing: station)) }
    if phase == .transferring { return L10n.text("在 %@ 换乘", String(describing: station)) }
    return L10n.text("前往 %@", String(describing: j.legs.last?.alighting?.name ?? ""))
  }
  @ViewBuilder private func passengerControls(_ j: Journey, phase: Phase?) -> some View {
    if !j.trackingEnded && !Projection.isUpcoming(j, now: store.qaDate ?? Date())
      && (phase == .beforeDeparture || phase == .onTheWay) {
      Button(phase == .beforeDeparture ? L10n.text("我已出门，前往车站") : L10n.text("我已到达车站")) {
        store.confirmPassengerProgress(id, to: phase == .beforeDeparture ? .onTheWay : .waiting)
      }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("confirm-passenger-progress")
    }
  }
  private func phaseSteps(_ phase: Phase?) -> some View {
    HStack(spacing: 6) {
      ForEach([Phase.beforeDeparture, .onTheWay, .waiting, .riding], id: \.self) { item in
        if item != .beforeDeparture { Rectangle().fill(VIATheme.line).frame(width: 15, height: 1) }
        Text(item.title).font(.system(size: 10, weight: phase == item ? .semibold : .regular))
          .foregroundStyle(phase == item ? VIATheme.accent : VIATheme.muted)
      }
    }
  }
  @ViewBuilder private func phaseInformation(_ j: Journey, phase: Phase?) -> some View {
    if let leg = j.currentLeg {
      VIASectionLabel(title: phase == .transferring ? L10n.text("接续信息") : L10n.text("乘车信息"))
      VIACard(padding: 16, spacing: 0) {
        HStack {
          Label(L10n.text("上车站"), systemImage: "location")
          Spacer()
          Text(leg.boarding?.name ?? "")
        }.frame(minHeight: 48)
        VIADivider()
        HStack {
          Label(phase != .beforeDeparture && leg.boarding?.departure?.estimatedDate != nil
            ? L10n.text("火车预计发车") : L10n.text("火车计划发车"), systemImage: "tram.fill")
          Spacer()
          Text(
            Time.format(
              phase == .beforeDeparture ? leg.boarding?.departure?.scheduledDate : leg.boarding?.departure?.effectiveDate,
              zone: leg.boarding?.timeZone ?? "America/Toronto"))
        }.frame(minHeight: 48)
        VIADivider()
        HStack {
          Label(
            phase == .beforeDeparture ? L10n.text("前往耗时") : L10n.text("目的站"),
            systemImage: phase == .beforeDeparture ? "figure.walk" : "mappin.and.ellipse")
          Spacer()
          Text(
            phase == .beforeDeparture ? L10n.text("%@ 分钟", String(describing: j.travelToStationMinutes)) : leg.alighting?.name ?? ""
          )
        }.frame(minHeight: 48)
      }.font(.system(size: 14))
      if phase == .beforeDeparture { Notice(text: L10n.text("计划出门按你的设置计算。即使列车预计晚点，也不会自动推迟出门提醒。")) }
      if phase == .waiting { Notice(text: L10n.text("预计时间可能变化，请留意车站广播和登车安排。"), symbol: "bell") }
    }
  }
  @ViewBuilder private func hero(_ j: Journey, now: Date) -> some View {
    if Projection.isUpcoming(j, now: now) {
      UpcomingSummary(journey: j, now: now)
        .padding(.vertical, 17).padding(.horizontal, 19)
        .background(VIATheme.tintSurface, in: RoundedRectangle(cornerRadius: 24))
    } else {
      JourneyHero(journey: j, now: now, frozen: store.qaScenario != nil)
    }
  }
  @ViewBuilder private func timeline(_ j: Journey, now: Date) -> some View {
    if let leg = j.currentLeg {
      VStack(alignment: .leading, spacing: 9) {
        VIASectionLabel(
          title: j.legs.count > 1 ? L10n.text("当前段 · VIA %@", String(describing: leg.trainNumber)) : L10n.text("沿途站点"), detail: L10n.text("计划 / 预计"))
        StationTimeline(
          calls: leg.snapshot.calls, boardingIndex: leg.boardingIndex,
          alightingIndex: leg.alightingIndex, now: now,
          riding: Projection.state(j, now: now)?.phase == .riding)
      }
      .padding(contentWidth >= 800 ? 18 : 0)
      .background(
        contentWidth >= 800 ? VIATheme.surface : .clear, in: RoundedRectangle(cornerRadius: 22))
    }
  }
  @ViewBuilder private func connections(_ j: Journey, now: Date) -> some View {
    if let state = Projection.state(j, now: now), let number = state.nextTrainNumber,
      let minutes = state.connectionMinutes, j.legs.indices.contains(j.currentLegIndex + 1)
    {
      let next = j.legs[j.currentLegIndex + 1]
      VIACard {
        HStack {
          Label(L10n.text("下一段 · VIA %@", String(describing: number)), systemImage: "arrow.triangle.branch").font(.headline)
          Spacer()
        }
        Text("\(next.boarding?.name ?? "") → \(next.alighting?.name ?? "")")
        Text(
          L10n.text("计划发车 %@", String(describing: Time.format(next.boarding?.departure?.scheduledDate,zone:next.boarding?.timeZone ?? "America/Toronto",date:true)))
        ).font(.subheadline)
        Divider()
        let arrivalLabel = j.currentLeg?.alighting?.arrival?.estimatedDate == nil ? L10n.text("计划") : L10n.text("预计")
        Text(
          minutes >= 0
            ? L10n.text("%@到达后，距下一段计划发车 %@ 分钟", String(describing: arrivalLabel), String(describing: minutes))
            : L10n.text("%@到达比下一段计划发车晚 %@ 分钟", String(describing: arrivalLabel), String(describing: -minutes))
        ).font(
          .subheadline
        ).foregroundStyle(VIATheme.accent)
      }
    }
    if j.legs.count > 1 {
      DisclosureGroup(L10n.text("全部车段")) {
        ForEach(j.legs) { leg in
          VStack(alignment: .leading) {
            Text(
              "VIA \(leg.trainNumber) · \(leg.boarding?.name ?? "") → \(leg.alighting?.name ?? "")")
            Text(
              "\(Time.format(leg.boarding?.departure?.scheduledDate,zone:leg.boarding?.timeZone ?? "America/Toronto",date:true)) → \(Time.format(leg.alighting?.arrival?.scheduledDate,zone:leg.alighting?.timeZone ?? "America/Toronto",date:true))"
            ).font(.caption).foregroundStyle(.secondary)
          }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
        }
      }
    }
  }
  @ViewBuilder private func map(_ j: Journey) -> some View {
    if let leg = j.currentLeg {
      TrainMap(
        train: leg.snapshot, origin: leg.boarding?.name ?? "", destination: leg.alighting?.name ?? "",
        now: store.qaDate, isOffline: store.isOffline, reference: leg.source == .reference,
        height: contentWidth >= 800 ? 270 : 160
      ).id(leg.id)
    }
  }
  private func controls(_ j: Journey, now: Date) -> some View {
    VStack(spacing: 14) {
      if j.trackingEnded {
        Notice(text: L10n.text("追踪已结束，行程仍保存在本机。可开启实时活动继续追踪。"), symbol: "stop.circle")
      }
      let upcoming = Projection.isUpcoming(j, now: now)
      HStack {
        Text(
          store.activities.journeyID == j.id
            ? L10n.text("实时活动进行中")
            : !upcoming
              ? L10n.text("实时活动未开启")
              : store.wantsAutoStart(j.id) ? L10n.text("出门前 5 小时自动开启实时活动") : L10n.text("实时活动不会自动开启")
        ).font(.caption).foregroundStyle(.secondary)
        Spacer()
        if !j.completed && upcoming && store.activities.journeyID != j.id {
          Button(store.wantsAutoStart(j.id) ? L10n.text("取消自动开启") : L10n.text("到时自动开启")) {
            store.setAutoStart(j, !store.wantsAutoStart(j.id))
          }.frame(minHeight: 44)
        } else if !j.completed {
          Button {
            activityActionPending = true
            Task {
              defer { activityActionPending = false }
              await store.activities.restore()
              if store.activities.journeyID == j.id {
                await store.activities.end()
              } else {
                await store.startActivity(j)
              }
            }
          } label: {
            HStack(spacing: 6) {
              if activityActionPending || store.isStartingActivity || store.activities.isChanging { ProgressView() }
              Text(store.activities.journeyID == j.id ? L10n.text("关闭实时活动") : L10n.text("开启实时活动"))
            }
          }.frame(minHeight: 44).disabled(activityActionPending || store.isStartingActivity || store.activities.isChanging)
        }
      }
      if let message = store.activities.feedback(for: j.id) {
        Text(message).font(.caption).foregroundStyle(.secondary)
      }
      if !store.activities.enabled { Notice(text: L10n.text("系统未允许实时活动，请在设置中开启。行程仍可在 App 内查看。")) }
    }
  }

}
struct StationTimeline: View {
  var calls: [StationCall]
  var boardingIndex: Int?
  var alightingIndex: Int?
  var now = Date()
  var riding = false
  var plannedOnly = false
  @Environment(\.dynamicTypeSize) private var typeSize
  private var visibleCalls: [StationCall] {
    calls.filter {
      (boardingIndex == nil || $0.index >= boardingIndex!)
        && (alightingIndex == nil || $0.index <= alightingIndex!)
    }
  }
  var body: some View {
    let visibleCalls = visibleCalls
    let lastIndex = visibleCalls.last?.index
    let nextIndex = riding ? visibleCalls.first {
      $0.reached != true && (($0.arrival ?? $0.departure)?.effectiveDate.map { $0 > now } ?? false)
    }?.index : boardingIndex
    VStack(spacing: 0) {
      ForEach(visibleCalls) { call in
        let rawEvent = call.index == boardingIndex ? call.departure : call.arrival ?? call.departure
        let event = plannedOnly ? rawEvent.map { EventTime(scheduled: $0.scheduled) } : rawEvent
        let passed = !plannedOnly && (call.reached == true || (riding && (event?.effectiveDate.map { $0 < now } ?? false)))
        let current = call.index == nextIndex
        HStack(alignment: .top, spacing: 9) {
          ZStack(alignment: .top) {
            if call.index != lastIndex {
              Rectangle().fill(passed ? VIATheme.yellow : VIATheme.line).frame(width: 2).padding(
                .top, 9)
            }
            Circle().fill(current || passed ? VIATheme.yellow : VIATheme.surface)
              .overlay(
                Circle().stroke(current || passed ? VIATheme.accent : VIATheme.muted, lineWidth: 2)
              )
              .frame(width: current ? 11 : 7, height: current ? 11 : 7)
              .background {
                if current {
                  Circle().fill(VIATheme.yellow.opacity(0.25)).frame(width: 17, height: 17)
                }
              }
              .padding(.top, 5)
          }.frame(width: 18).accessibilityHidden(true)
          (typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .top))) {
              VStack(alignment: .leading, spacing: 3) {
                Text(call.name).font(.system(size: 14, weight: .medium))
                  .foregroundStyle(passed ? VIATheme.muted : VIATheme.ink)
                Text(description(call, passed: passed, current: current, event: event))
                  .font(.system(size: 11)).foregroundStyle(VIATheme.muted)
              }
              if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
              VStack(alignment: .trailing, spacing: 3) {
                Text(Time.format(event?.effectiveDate, zone: call.timeZone))
                  .font(.system(size: 15)).foregroundStyle(
                    current ? VIATheme.accent : passed ? VIATheme.muted : VIATheme.ink)
                if let estimated = event?.estimatedDate, let scheduled = event?.scheduledDate,
                  abs(estimated.timeIntervalSince(scheduled)) >= 60
                {
                  Text(Time.format(scheduled, zone: call.timeZone)).strikethrough()
                    .font(.system(size: 11)).foregroundStyle(VIATheme.muted)
                }
                // Show a date or timezone only where it changes the interpretation of the time.
                if let date = event?.effectiveDate, let first = visibleCalls.first,
                  let firstDate = (first.departure ?? first.arrival)?.effectiveDate,
                  VIATheme.date(date, zone: call.timeZone, format: "yyyy-MM-dd")
                    != VIATheme.date(firstDate, zone: first.timeZone, format: "yyyy-MM-dd")
                    || call.timeZone != first.timeZone
                {
                  Text(VIATheme.date(date, zone: call.timeZone, format: "M/d z"))
                    .font(.system(size: 10)).foregroundStyle(VIATheme.muted)
                }
              }.monospacedDigit()
            }.padding(.bottom, call.index == visibleCalls.last?.index ? 0 : 13)
        }.fixedSize(horizontal: false, vertical: true).accessibilityElement(children: .combine)
      }
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
  private func description(_ call: StationCall, passed: Bool, current: Bool, event: EventTime?)
    -> String
  {
    if passed { return call.index == alightingIndex || call.index == visibleCalls.last?.index ? L10n.text("已到达") : L10n.text("已到站") }
    let prefix =
      call.index == alightingIndex
      ? L10n.text("目的站") : current && riding ? L10n.text("下一站") : call.index == boardingIndex ? L10n.text("上车站") : L10n.text("沿途站")
    return
      "\(prefix) · \(L10n.eventTitle(estimated: event?.estimatedDate != nil, arrival: call.index != boardingIndex))"
  }
}
// Both saved journeys and train details use the same live snapshot and map controls.
struct TrainMap: View {
  var train: TrainSnapshot
  var origin: String
  var destination: String
  var now: Date? = nil
  var isOffline = false
  var reference = false
  var height: CGFloat = 160
  @State private var expanded = false
  @State private var showingRoute = false
  private var validPosition: TrainPosition? {
    guard let position = train.position, position.latitude.isFinite, position.longitude.isFinite,
      CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(
        latitude: position.latitude, longitude: position.longitude)) else { return nil }
    return position
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        VIASectionLabel(title: L10n.text("列车位置"), detail: "VIA \(train.trainNumber)")
        Spacer()
        Button(L10n.text("线路图"), systemImage: "point.topleft.down.to.point.bottomright.curvepath") { showingRoute = true }
          .font(.caption).frame(minHeight: 44)
      }
      if let position = validPosition {
        TrainPositionMap(trainNumber: train.trainNumber, position: position, interactive: false)
          .frame(height: height).clipShape(RoundedRectangle(cornerRadius: 18))
          .overlay(alignment: .bottomTrailing) {
            Button(L10n.text("展开地图"), systemImage: "arrow.up.left.and.arrow.down.right") { expanded = true }
              .font(.system(size: 12, weight: .medium)).padding(.horizontal, 12).frame(minHeight: 44)
              .background(VIATheme.surface, in: Capsule()).padding(10)
          }
        positionCaption(position)
        if isOffline {
          Text(L10n.text("离线显示最近的列车位置，底图可能无法加载。"))
            .font(.caption).foregroundStyle(VIATheme.muted)
        }
      } else {
        VIACard(padding: 16, spacing: 12) {
          Label(L10n.text("暂无列车定位"), systemImage: "map").font(.subheadline)
          ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
              Text(origin)
              Image(systemName: "arrow.right").foregroundStyle(VIATheme.accent)
              Text(destination)
            }
            VStack(alignment: .leading, spacing: 8) {
              Text(origin)
              Label(destination, systemImage: "arrow.down")
            }
          }.font(.headline)
          Text(L10n.text("可查看沿途站点。列车位置可用时，地图会自动显示。"))
            .font(.caption).foregroundStyle(VIATheme.muted)
        }
      }
      if !train.departed, !train.arrived, let first = train.calls.first {
        HStack {
          Label(L10n.text("始发站 · %@", String(describing: first.name)), systemImage: "mappin.circle").font(.subheadline)
          Spacer()
          Text(Time.format(first.departure?.effectiveDate, zone: first.timeZone))
            .font(.subheadline.monospacedDigit())
        }
      } else if let next = train.calls.first(where: {
        $0.reached != true && ($0.arrival?.effectiveDate.map { $0 > (now ?? Date()) } ?? false)
      }), !train.arrived {
        HStack {
          Label(L10n.text("下一站 · %@", String(describing: next.name)), systemImage: "mappin.circle").font(.subheadline)
          Spacer()
          Text(Time.format(next.arrival?.effectiveDate, zone: next.timeZone))
            .font(.subheadline.monospacedDigit())
        }
      }
    }
    .sheet(isPresented: $showingRoute) {
      NavigationStack {
        ScrollView {
          VStack(alignment: .leading, spacing: 20) {
            Text("\(train.from) → \(train.to)").font(.title3.bold())
            Text(L10n.text("沿途站点示意")).font(.subheadline).foregroundStyle(.secondary)
            TimelineView(.periodic(from: .now, by: 30)) { context in
              StationTimeline(calls: train.calls, now: now ?? context.date, riding: train.departed)
            }
            officialMapLink
          }.padding(24).frame(maxWidth: 700).frame(maxWidth: .infinity)
        }.viaBackground().navigationTitle(L10n.text("VIA %@ · 线路图", String(describing: train.trainNumber)))
          .navigationBarTitleDisplayMode(.inline)
          .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.text("完成")) { showingRoute = false } } }
      }.presentationDetents([.large])
    }
    .sheet(isPresented: $expanded) {
      NavigationStack {
        Group {
          if let position = validPosition {
            TrainPositionMap(trainNumber: train.trainNumber, position: position, interactive: true)
              .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                  Text("\(origin) → \(destination)").font(.headline)
                  positionCaption(position)
                  officialMapLink
                  if isOffline { Text(L10n.text("离线 · 按最近位置显示，底图可能无法加载")).font(.caption) }
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                  .background(VIATheme.background)
              }
          } else {
            ContentUnavailableView(L10n.text("暂无列车定位"), systemImage: "map",
              description: Text(L10n.text("暂未收到有效坐标，稍后会自动更新。")))
          }
        }.viaBackground().navigationTitle(L10n.text("VIA %@ · 列车位置", String(describing: train.trainNumber)))
          .navigationBarTitleDisplayMode(.inline)
          .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.text("完成")) { expanded = false } } }
      }.presentationDetents([.large]).presentationDragIndicator(.visible)
    }
  }
  @ViewBuilder private var officialMapLink: some View {
    // rawKey preserves the date suffix when VIA lists multiple runs of one train.
    let key = train.rawKey.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? train.trainNumber
    if reference {
      Text(L10n.text("这天的列车位置尚未提供。")).font(.caption).foregroundStyle(.secondary)
    } else {
      Link(L10n.text("在 VIA 官网查看地图"), destination: URL(string: "https://tsimobile.viarail.ca/#\(key)")!)
        .font(.subheadline).frame(minHeight: 44)
    }
  }
  private func positionCaption(_ position: TrainPosition) -> some View {
    TimelineView(.periodic(from: .now, by: 30)) { context in
      let reported = position.reportedAt.flatMap(Time.parse)
      let stale = reported.map { (now ?? context.date).timeIntervalSince($0) > 300 } ?? true
      HStack(spacing: 12) {
        if let speed = position.speedKmh, speed.isFinite, !stale, !isOffline {
          Label("\(Int(speed.rounded())) km/h", systemImage: "speedometer")
        }
        Label(reported.map {
          L10n.text("%@ 更新%@", String(describing: Time.format($0)), String(describing: stale ? L10n.text(" · 最近位置") : ""))
        } ?? L10n.text("最近位置"), systemImage: stale ? "clock" : "location.fill")
      }.font(.caption).foregroundStyle(stale ? VIATheme.amber : VIATheme.muted)
    }
  }
}
private struct TrainPositionMap: View {
  var trainNumber: String
  var position: TrainPosition
  var interactive: Bool
  @State private var camera: MapCameraPosition = .automatic
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private var coordinate: CLLocationCoordinate2D {
    CLLocationCoordinate2D(latitude: position.latitude, longitude: position.longitude)
  }
  var body: some View {
    Map(position: $camera, interactionModes: interactive ? .all : []) {
      Annotation("VIA \(trainNumber)", coordinate: coordinate) {
        VStack(spacing: 3) {
          if let heading = position.heading, heading.isFinite {
            Image(systemName: "location.north.fill").rotationEffect(.degrees(heading))
              .font(.caption).foregroundStyle(VIATheme.accent)
          }
          Image(systemName: "tram.fill")
        }.padding(10).foregroundStyle(VIATheme.ink)
          .background(VIATheme.tintSurface, in: Circle())
          .overlay(Circle().stroke(VIATheme.accent, lineWidth: 2))
          .accessibilityLabel(L10n.text("VIA %@ 最近上报的位置", String(describing: trainNumber)))
      }
    }
    .mapControls {
      if interactive {
        MapCompass()
        MapScaleView()
      }
    }
    .overlay(alignment: .bottomTrailing) {
      if interactive {
        Button {
          withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { recenter() }
        } label: {
          Label(L10n.text("回到列车"), systemImage: "location.fill")
            .font(.system(size: 14, weight: .medium)).padding(.horizontal, 16).frame(minHeight: 48)
        }.buttonStyle(.plain).foregroundStyle(VIATheme.accent)
          .background(VIATheme.surface, in: Capsule()).padding(16)
      }
    }
    .onAppear { recenter() }
    .onChange(of: position) { _, _ in
      // Keep the user's chosen area while they inspect the expanded map.
      if !interactive || !camera.positionedByUser { recenter() }
    }
  }
  private func recenter() {
    camera = .region(MKCoordinateRegion(center: coordinate,
      span: MKCoordinateSpan(latitudeDelta: 0.25, longitudeDelta: 0.25)))
  }
}
