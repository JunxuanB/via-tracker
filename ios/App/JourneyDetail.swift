import MapKit
import SwiftUI
import TrackerCore

struct JourneyDetail: View {
  @Bindable var store: AppStore
  var id: String
  @Environment(\.horizontalSizeClass) private var sizeClass
  @Environment(\.dismiss) private var dismiss
  @Environment(\.dynamicTypeSize) private var typeSize
  @State private var editing = false
  @State private var correcting = false
  @State private var ending = false
  @State private var deleting = false
  @State private var contentWidth: CGFloat = 0
  private var journey: Journey? { store.journeys.first { $0.id == id } }
  var body: some View {
    Group {
      if let j = journey {
        ScrollView {
          VStack(alignment: .leading, spacing: 20) {
            (typeSize.isAccessibilitySize
              ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
              : AnyLayout(HStackLayout(alignment: .top))) {
                VStack(alignment: .leading, spacing: 6) {
                  Text(j.displayTitle).font(.title2.bold())
                  Text("\(j.legs.count) 段列车 · \(j.legs.first?.originServiceDate ?? "")").font(
                    .subheadline
                  ).foregroundStyle(.secondary)
                }
                if !typeSize.isAccessibilitySize { Spacer() }
                StatusPill(
                  title: j.currentLeg?.source == .reference
                    ? "待同步" : store.isOffline ? "离线" : "已获取",
                  symbol: store.isOffline ? "wifi.slash" : "antenna.radiowaves.left.and.right")
              }
            if let message = store.sourceMessage {
              Notice(text: message, symbol: store.isOffline ? "wifi.slash" : "wifi.exclamationmark")
            }
            if let fetched = j.currentLeg.flatMap({ Time.parse($0.snapshot.sourceFetchedAt) }),
              (store.qaDate ?? Date()).timeIntervalSince(fetched) > 600
            {
              Notice(text: "列车数据已超过 10 分钟 · 按最近有效时刻显示", symbol: "clock.badge.exclamationmark")
            }
            if j.pendingScheduleChange {
              VIACard(tinted: true) {
                Text("正式时刻与规划不同").font(.headline)
                Text("是否同步本行程的规划发车时间？之后官方计划变化也将遵循本次选择。").font(.subheadline)
                Button("同步本行程规划") {
                  var changed = j
                  changed.chooseSync(true)
                  store.save(changed)
                }.buttonStyle(PrimaryButtonStyle())
                Button("保留我的规划") {
                  var changed = j
                  changed.chooseSync(false)
                  store.save(changed)
                }.frame(minHeight: 44)
              }
            }
            if j.currentLeg?.source == .reference { Notice(text: "参考时刻，待同步。不代表目标日期一定开行。") }
            if sizeClass == .regular && contentWidth >= 800 {
              HStack(alignment: .top, spacing: 24) {
                VStack(spacing: 20) {
                  hero(j)
                  map(j)
                  controls(j)
                }.frame(maxWidth: .infinity)
                VStack(spacing: 20) {
                  timeline(j)
                  connections(j)
                }.frame(maxWidth: .infinity)
              }
            } else {
              hero(j)
              timeline(j)
              connections(j)
              map(j)
              controls(j)
            }
            if let leg = j.currentLeg {
              Text(
                "获取于 \(Time.format(Time.parse(leg.snapshot.sourceFetchedAt),date:true)) · 进度按时刻推算"
              ).font(.caption).foregroundStyle(.secondary)
              ForEach(Array(leg.snapshot.alerts.enumerated()), id: \.offset) { _, alert in
                VIACard {
                  Text(alert.title).font(.headline)
                  Text(alert.body).font(.subheadline)
                  if let value = alert.url, let url = URL(string: value),
                    ["https", "http"].contains(url.scheme ?? "")
                  {
                    Link("查看原始通知", destination: url)
                  }
                }
              }
            }
            if let error = store.syncError { Notice(text: error) }
          }.padding(24).frame(maxWidth: 1200).frame(maxWidth: .infinity)
        }.refreshable { await store.refresh() }
          .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { contentWidth = $0 }
      } else {
        ContentUnavailableView("行程不存在", systemImage: "tram")
      }
    }
    .viaBackground().navigationTitle("行程详情").navigationBarTitleDisplayMode(.inline)
    .toolbar {
      Menu {
        Button("编辑行程", systemImage: "slider.horizontal.3") { editing = true }
        Button("更正个人阶段", systemImage: "hand.tap") { correcting = true }
        if let j = journey { Button("设为主行程", systemImage: "location.fill") { store.setPrimary(j) } }
        Button("结束追踪", systemImage: "stop.circle", role: .destructive) { ending = true }
        Button("删除行程", systemImage: "trash", role: .destructive) { deleting = true }
      } label: {
        Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44)
      }.accessibilityLabel("管理行程")
    }
    .sheet(isPresented: $editing) {
      if let journey { AddJourneyFlow(store: store, initialJourney: journey) }
    }
    .task {
      if store.qaScenario == "correct-stage" { correcting = true }
      if store.qaScenario == "end-confirm" { ending = true }
    }
    .confirmationDialog("更正个人阶段", isPresented: $correcting, titleVisibility: .visible) {
      if let j = journey {
        ForEach(Phase.allCases.filter { $0 != .transferring || j.currentLegIndex > 0 }, id: \.self)
        { phase in
          Button(phase.title) {
            var changed = j
            changed.manualPhase = phase
            changed.completed = phase == .completed
            store.save(changed)
          }
        }
        Button("恢复自动判断") {
          var changed = j
          changed.manualPhase = nil
          changed.completed = false
          store.save(changed)
        }
      }
    }
    .confirmationDialog("结束追踪？", isPresented: $ending, titleVisibility: .visible) {
      Button("结束追踪", role: .destructive) { if let journey { store.stopTracking(journey) } }
    } message: {
      Text("实时活动会结束，行程仍保存在本机。")
    }
    .confirmationDialog("删除本机行程？", isPresented: $deleting, titleVisibility: .visible) {
      Button("删除行程", role: .destructive) {
        if let journey {
          store.delete(journey)
          dismiss()
        }
      }
    } message: {
      Text("此操作会移除行程并取消后台订阅。")
    }
  }
  private func hero(_ j: Journey) -> some View {
    TimelineView(.periodic(from: .now, by: 1)) { context in
      JourneyHero(journey: j, now: store.qaDate ?? context.date, frozen: store.qaScenario != nil)
    }
  }
  @ViewBuilder private func timeline(_ j: Journey) -> some View {
    if let leg = j.currentLeg {
      VStack(alignment: .leading, spacing: 12) {
        Text("当前段 · VIA \(leg.trainNumber)").font(.headline)
        StationTimeline(
          calls: leg.snapshot.calls, boardingIndex: leg.boardingIndex,
          alightingIndex: leg.alightingIndex)
      }
    }
  }
  @ViewBuilder private func connections(_ j: Journey) -> some View {
    if let state = Projection.state(j), let number = state.nextTrainNumber,
      let minutes = state.connectionMinutes, j.legs.indices.contains(j.currentLegIndex + 1)
    {
      let next = j.legs[j.currentLegIndex + 1]
      VIACard {
        HStack {
          Label("下一段 · VIA \(number)", systemImage: "arrow.triangle.branch").font(.headline)
          Spacer()
        }
        Text("\(next.boarding?.name ?? "") → \(next.alighting?.name ?? "")")
        Text(
          "计划发车 \(Time.format(next.boarding?.departure?.scheduledDate,zone:next.boarding?.timeZone ?? "America/Toronto",date:true))"
        ).font(.subheadline)
        Divider()
        let arrivalLabel = j.currentLeg?.alighting?.arrival?.estimatedDate == nil ? "计划" : "预计"
        Text(
          minutes >= 0
            ? "\(arrivalLabel)到达后，距下一段计划发车 \(minutes) 分钟"
            : "\(arrivalLabel)到达比下一段计划发车晚 \(-minutes) 分钟"
        ).font(
          .subheadline
        ).foregroundStyle(VIATheme.accent)
      }
    }
    if j.legs.count > 1 {
      DisclosureGroup("全部车段") {
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
    if let leg = j.currentLeg { TrainMap(leg: leg, now: store.qaDate) }
  }
  private func controls(_ j: Journey) -> some View {
    VStack(spacing: 14) {
      if !j.completed && !j.trackingEnded, let phase = Projection.state(j)?.phase {
        Button(action: {
          var changed = j
          switch phase {
          case .beforeDeparture: changed.manualPhase = .onTheWay
          case .onTheWay: changed.manualPhase = .waiting
          case .waiting, .transferring: changed.manualPhase = .riding
          case .riding: changed.advanceLeg()
          case .completed: break
          }
          store.save(changed)
        }) {
          Label(
            actionTitle(phase, j: j),
            systemImage: phase == .riding ? "checkmark.circle" : "hand.tap")
        }.buttonStyle(PrimaryButtonStyle())
      }
      HStack {
        Text(store.activities.journeyID == j.id ? "实时活动进行中" : "实时活动未开启").font(.caption)
          .foregroundStyle(.secondary)
        Spacer()
        if !j.completed {
          Button(store.activities.journeyID == j.id ? "关闭活动" : "开启 / 续开") {
            Task {
              if store.activities.journeyID == j.id {
                await store.activities.end()
              } else {
                await store.startActivity(j)
              }
            }
          }.frame(minHeight: 44)
        }
      }
      if let message = store.activities.message {
        Text(message).font(.caption).foregroundStyle(.secondary)
      }
      if !store.activities.enabled { Notice(text: "系统未允许实时活动，请在设置中开启。行程仍可在 App 内查看。") }
    }
  }
  private func actionTitle(_ phase: Phase, j: Journey) -> String {
    switch phase {
    case .beforeDeparture: "已出门"
    case .onTheWay: "已到站"
    case .waiting, .transferring: "已上车"
    case .riding: j.currentLegIndex + 1 < j.legs.count ? "已到换乘站" : "确认已到达"
    case .completed: "已完成"
    }
  }
}
struct StationTimeline: View {
  var calls: [StationCall]
  var boardingIndex: Int?
  var alightingIndex: Int?
  @Environment(\.dynamicTypeSize) private var typeSize
  var body: some View {
    VIACard {
      ForEach(calls) { call in
        let selected =
          (boardingIndex == nil || call.index >= boardingIndex!)
          && (alightingIndex == nil || call.index <= alightingIndex!)
        let event = call.index == boardingIndex ? call.departure : call.arrival ?? call.departure
        HStack(alignment: .top, spacing: 14) {
          VStack(spacing: 5) {
            Image(
              systemName: call.index == boardingIndex || call.index == alightingIndex
                ? "circle.inset.filled" : "circle"
            )
            .font(.caption).foregroundStyle(selected ? VIATheme.accent : .secondary)
            if call.index != calls.last?.index {
              Rectangle().fill(selected ? VIATheme.yellow.opacity(0.6) : .secondary.opacity(0.2))
                .frame(width: 2).frame(minHeight: 44)
            }
          }.accessibilityHidden(true)
          (typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top))) {
              VStack(alignment: .leading, spacing: 5) {
                Text(call.name).font(.headline)
                Text(
                  call.index == boardingIndex
                    ? "上车站 · 发车"
                    : call.index == alightingIndex
                      ? "下车站 · 到达" : event?.estimatedDate == nil ? "计划到站" : "预计到站"
                )
                .font(.caption).foregroundStyle(.secondary)
                Text(call.timeZone).font(.caption2).foregroundStyle(.secondary)
              }
              if !typeSize.isAccessibilitySize { Spacer() }
              VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 5) {
                Text(Time.format(event?.effectiveDate, zone: call.timeZone, date: true))
                  .monospacedDigit()
                if event?.estimatedDate != nil {
                  Text(Time.format(event?.scheduledDate, zone: call.timeZone)).strikethrough().font(
                    .caption
                  ).foregroundStyle(.secondary)
                } else {
                  Text("按计划").font(.caption).foregroundStyle(.secondary)
                }
              }
            }
        }.opacity(selected ? 1 : 0.5).accessibilityElement(children: .combine)
      }
    }
  }
}
struct TrainMap: View {
  var leg: TrainLeg
  var now: Date? = nil
  @State private var expanded = false
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      if let position = leg.snapshot.position {
        let coordinate = CLLocationCoordinate2D(
          latitude: position.latitude, longitude: position.longitude)
        Map(
          initialPosition: .region(
            MKCoordinateRegion(
              center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.3, longitudeDelta: 0.3)))
        ) {
          Annotation("VIA \(leg.trainNumber)", coordinate: coordinate) {
            Image(systemName: "tram.fill").padding(10).foregroundStyle(.black).background(
              VIATheme.yellow, in: Circle())
          }
        }.frame(height: expanded ? 420 : 190).clipShape(RoundedRectangle(cornerRadius: 22))
        HStack {
          Text(
            position.reportedAt.flatMap(Time.parse).map {
              "位置上报 \(Time.format($0,date:true))\((now ?? Date()).timeIntervalSince($0)>300 ? " · 定位较旧":"")"
            } ?? "位置上报时间未知"
          ).font(.caption).foregroundStyle(.secondary)
          Spacer()
          Button(expanded ? "收起地图" : "展开地图", systemImage: "arrow.up.left.and.arrow.down.right") {
            expanded.toggle()
          }.labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
        }
      } else {
        VIACard {
          Label("路线示意 · 暂无列车定位", systemImage: "map").font(.subheadline).foregroundStyle(.secondary)
          HStack {
            Text(leg.boarding?.name ?? "")
            Image(systemName: "arrow.right").foregroundStyle(VIATheme.accent)
            Text(leg.alighting?.name ?? "")
          }.font(.headline)
          Text("此示意不代表实际铁路轨迹。").font(.caption).foregroundStyle(.secondary)
        }
      }
    }
  }
}
