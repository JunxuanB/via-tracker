import SwiftUI
import TrackerCore

struct RootView: View {
  @Bindable var store: AppStore
  @Binding var pendingURL: URL?
  @Environment(\.horizontalSizeClass) private var sizeClass
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.dynamicTypeSize) private var userTypeSize
  @State private var tab = 0
  @State private var compactNavigationID = UUID()
  @State private var adding = false
  @State private var sidebar: String? = "journeys"
  @State private var sidebarResetID = UUID()
  var body: some View {
    Group {
      #if DEBUG
        if let scenario = store.qaScenario,
          ["lock-light", "lock-dark", "ipad-lock", "live-states", "islands", "widgets"].contains(
            scenario)
        {
          NavigationStack {
            SystemComponentGallery(
              scenario: scenario, initialJourney: store.journeys.first ?? PreviewScenarios.base)
          }
        } else {
          content
        }
      #else
        content
      #endif
    }.preferredColorScheme(
      store.appearance == "dark" ? .dark : store.appearance == "light" ? .light : nil
    )
    .frame(
      width: store.qaScenario == "ipad-narrow"
        ? 600 : store.qaScenario == "small-device" ? 320 : nil
    )
    .dynamicTypeSize(store.qaScenario == "large-text" ? .accessibility5 : userTypeSize)
  }
  private var content: some View {
    Group {
      if sizeClass == .regular && store.qaScenario != "ipad-narrow" {
        HStack(spacing: 0) {
          VStack(alignment: .leading, spacing: 18) {
            Text("Train Tracker").font(.system(size: 27, weight: .semibold)).padding(.horizontal, 10)
            ForEach(
              Array(
                [
                  ("journeys", "我的行程", "house.fill"), ("trains", "列车列表", "tram.fill"),
                  ("history", "历史行程", "clock.arrow.circlepath"), ("settings", "设置", "gearshape"),
                ].enumerated()), id: \.offset
            ) { _, item in
              Button {
                selectSidebar(item.0)
              } label: {
                Label(item.1, systemImage: item.2).font(.system(size: 14, weight: .medium))
                  .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                  .frame(minHeight: 48).contentShape(Rectangle())
                  .background(
                    sidebar == item.0 ? VIATheme.tintSurface : .clear,
                    in: RoundedRectangle(cornerRadius: 12))
              }.buttonStyle(SidebarButtonStyle())
                .accessibilityAddTraits(sidebar == item.0 ? .isSelected : [])
            }
            VIADivider()
            Text("已保存的行程").font(.system(size: 11)).foregroundStyle(VIATheme.muted).padding(
              .horizontal, 12)
            ScrollView {
              VStack(spacing: 4) {
                ForEach(store.activeJourneys) { j in
                  Button {
                    selectSidebar(j.id)
                  } label: {
                    VStack(alignment: .leading, spacing: 7) {
                      Text(j.displayTitle).font(.system(size: 14, weight: .medium))
                      Text(j.legs.map { "VIA \($0.trainNumber)" }.joined(separator: " + "))
                        .font(.system(size: 11)).foregroundStyle(VIATheme.muted)
                    }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                      .frame(minHeight: 56).contentShape(Rectangle())
                      .background(
                        sidebar == j.id ? VIATheme.tintSurface : .clear,
                        in: RoundedRectangle(cornerRadius: 12))
                  }.buttonStyle(SidebarButtonStyle())
                    .accessibilityAddTraits(sidebar == j.id ? .isSelected : [])
                }
              }
            }
            Button("添加行程", systemImage: "plus") { adding = true }.buttonStyle(
              SecondaryButtonStyle())
            Text("行程保存在本机 · 支持离线查看").font(.system(size: 10)).foregroundStyle(VIATheme.muted)
          }.padding(.horizontal, 17).padding(.vertical, 24).frame(width: 256)
            .background(VIATheme.tintSurface.opacity(0.25))
          Rectangle().fill(VIATheme.line).frame(width: 1)
          NavigationStack {
            if sidebar == "settings" {
              SettingsView(store: store)
            } else if sidebar == "history" {
              JourneyHistory(store: store, showsBackButton: false)
            } else if sidebar == "trains" {
              TrainBrowser(store: store)
            } else if let j = store.journeys.first(where: { $0.id == sidebar }) {
              JourneyDetail(store: store, id: j.id)
            } else {
              JourneyHome(store: store, adding: $adding, onSelect: selectSidebar)
            }
          }.id(sidebar).id(sidebarResetID)
        }
      } else {
        NavigationStack {
          // Reserve actual layout space for tabs; pushed destinations do not inherit them.
          VStack(spacing: 0) {
            Group {
              if tab == 0 {
                JourneyHome(store: store, adding: $adding, onSelect: { store.selectedJourneyID = $0 })
              } else if tab == 1 {
                TrainBrowser(store: store)
              } else {
                SettingsView(store: store)
              }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            bottomNavigation
          }.navigationDestination(item: $store.selectedJourneyID) { id in
            JourneyDetail(store: store, id: id, showsBackButton: true)
          }
        }.id(compactNavigationID)
      }
    }.viaBackground().preferredColorScheme(
      store.appearance == "dark" ? .dark : store.appearance == "light" ? .light : nil
    )
    .sheet(isPresented: Binding(get: { adding && sizeClass == .regular }, set: { adding = $0 })) {
      AddJourneyFlow(store: store)
    }
    .fullScreenCover(
      isPresented: Binding(get: { adding && sizeClass != .regular }, set: { adding = $0 })
    ) { AddJourneyFlow(store: store) }
    .onChange(of: pendingURL, initial: true) { _, url in
      guard let url else { return }
      open(url)
      pendingURL = nil
    }
    .task {
      if let id = store.selectedJourneyID { sidebar = id }
      if let scenario = store.qaScenario {
        if scenario == "settings" {
          tab = 2
          sidebar = "settings"
        }
        if [
          "search", "date", "stations", "boarding-picker", "alighting-picker", "departure",
          "travel", "review", "add-transfer", "transfer-unavailable", "transfer-review", "edit",
          "ipad-create", "manual-warning",
        ].contains(scenario) {
          adding = true
        }
      }
      store.foreground(true)
      await store.activateSystemServices()
      await store.checkNotifications()
      if store.notificationStatus == "已允许" && store.qaScenario == nil && store.supportsRemotePush {
        UIApplication.shared.registerForRemoteNotifications()
      }
    }
    .onChange(of: scenePhase) { _, phase in
      store.foreground(phase == .active)
      if phase == .active {
        Task {
          await store.activities.restore()
          await store.checkNotifications()
          if store.notificationStatus == "已允许" && store.qaScenario == nil && store.supportsRemotePush {
            UIApplication.shared.registerForRemoteNotifications()
          }
        }
      }
    }
    .onChange(of: store.selectedJourneyID) { _, id in if let id { sidebar = id } }
    .onChange(of: store.journeys.map(\.id)) { _, ids in
      if let id = store.selectedJourneyID, !ids.contains(id) { store.selectedJourneyID = nil }
      if let sidebar, !["journeys", "trains", "settings", "history"].contains(sidebar), !ids.contains(sidebar) {
        self.sidebar = "journeys"
      }
    }
    .alert(
      "本地存储需要处理",
      isPresented: Binding(
        get: { store.storageError != nil }, set: { if !$0 { store.storageError = nil } })
    ) {
      Button("好", role: .cancel) {}
    } message: {
      Text(store.storageError ?? "")
    }
  }
  private func selectSidebar(_ destination: String) {
    // A repeated tap on the selected category returns from its pushed detail to the root.
    if sidebar == destination { sidebarResetID = UUID() }
    store.selectedJourneyID = nil
    tab = destination == "settings" ? 2 : destination == "trains" ? 1 : 0
    sidebar = destination
  }
  private func open(_ url: URL) {
    guard url.scheme == "viatracker" else { return }
    adding = false
    compactNavigationID = UUID()
    sidebarResetID = UUID()
    store.selectedJourneyID = nil
    switch url.host {
    case "settings": tab = 2; sidebar = "settings"
    case "trains": tab = 1; sidebar = "trains"
    case "journey":
      tab = 0
      let id = url.lastPathComponent == "current" ? store.primaryJourney?.id : url.lastPathComponent
      if let id, store.journeys.contains(where: { $0.id == id }) {
        store.selectedJourneyID = id
        sidebar = id
      } else { sidebar = "journeys" }
    default: tab = 0; sidebar = "journeys"
    }
  }
  private var bottomNavigation: some View {
    HStack(spacing: 0) {
      ForEach(0..<3) { index in
        Button {
          store.selectedJourneyID = nil
          tab = index
        } label: {
          VStack(spacing: 4) {
            Image(
              systemName: [tab == 0 ? "house.fill" : "house", "tram.fill", "gearshape"][index]
            )
            .font(.system(size: 21))
            Text(["行程", "列车", "设置"][index]).font(.system(size: 10))
          }.frame(maxWidth: .infinity).frame(height: 53).contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(tab == index ? VIATheme.accent : VIATheme.muted)
          .accessibilityAddTraits(tab == index ? .isSelected : [])
      }
    }.padding(.horizontal, 16).padding(.top, 4)
      .background(VIATheme.background.ignoresSafeArea(edges: .bottom))
      .overlay(alignment: .top) { VIADivider() }
      .accessibilityIdentifier("bottom-navigation")
  }

}
struct JourneyHome: View {
  @Bindable var store: AppStore
  @Binding var adding: Bool
  var onSelect: (String) -> Void
  @Environment(\.dynamicTypeSize) private var typeSize
  var body: some View {
    GeometryReader { geometry in
      ScrollView {
        VStack(alignment: .leading, spacing: 17) {
          HStack {
            VStack(alignment: .leading, spacing: 5) {
              if !store.journeys.isEmpty {
                Text(VIATheme.date(store.qaDate ?? Date())).font(.system(size: 12)).foregroundStyle(
                  VIATheme.muted)
              }
              Text("我的行程").font(.system(size: 32, weight: .semibold)).tracking(-1.5)
            }
            Spacer()
            Button("添加行程", systemImage: "plus") { adding = true }
              .labelStyle(.iconOnly).font(.system(size: 21)).foregroundStyle(VIATheme.accent).frame(
                width: 44, height: 44)
          }
          if let message = store.sourceMessage {
            Notice(text: message, symbol: store.isOffline ? "wifi.slash" : "wifi.exclamationmark")
          }
          if store.journeys.isEmpty {
            Spacer(minLength: 35)
            VStack(spacing: 18) {
              ZStack {
                Circle().stroke(VIATheme.line, lineWidth: 1).frame(width: 122, height: 122)
                Circle().fill(VIATheme.tintSurface).frame(width: 90, height: 90)
                Image(systemName: "tram.fill").font(.system(size: 44)).foregroundStyle(
                  VIATheme.accent)
              }.frame(height: 150)
              Text("还没有行程").font(.system(size: 20, weight: .semibold))
              Text("添加列车，查看出门、乘车和换乘时间。\n支持离线查看最近的数据。")
                .font(.system(size: 13)).lineSpacing(8).multilineTextAlignment(.center)
                .foregroundStyle(VIATheme.muted)
            }.frame(maxWidth: .infinity)
            Button("添加第一趟行程", systemImage: "plus") { adding = true }.buttonStyle(
              PrimaryButtonStyle()
            ).padding(.top, 10)
            Spacer(minLength: 35)
            Notice(text: "无需账号。行程保存在这台设备上，断网时也能查看最近的信息。")
          } else {
            if let j = store.primaryJourney {
              HStack {
                Text("当前行程").font(.system(size: 13, weight: .semibold))
                Spacer()
                StatusPill(title: "主行程", symbol: "location.fill")
              }
              Button {
                onSelect(j.id)
              } label: {
                TimelineView(.periodic(from: .now, by: 15)) { context in
                  homeCard(j, now: store.qaDate ?? context.date)
                }
              }.buttonStyle(.plain)
            }
            let others = store.activeJourneys.filter { $0.id != store.primaryJourney?.id }
            if !others.isEmpty {
              VIASectionLabel(title: "接下来的行程")
              ForEach(others) { journey in
                Button { onSelect(journey.id) } label: {
                  SavedJourneyCard(journey: journey, now: store.qaDate ?? store.clockNow)
                }.buttonStyle(.plain)
              }
            }
            if store.activeJourneys.isEmpty {
              Notice(text: "暂无待出发的行程，准备好下一趟旅行时再添加。", symbol: "tram.fill")
            }
            if !store.recentJourneys.isEmpty {
              VIASectionLabel(title: "刚刚完成", detail: "在首页保留 24 小时")
              ForEach(store.recentJourneys) { journey in
                Button { onSelect(journey.id) } label: {
                  SavedJourneyCard(journey: journey, now: store.qaDate ?? store.clockNow)
                }.buttonStyle(.plain)
              }
            }
            NavigationLink {
              JourneyHistory(store: store)
            } label: {
              Label("历史行程 · \(store.historyJourneys.count)", systemImage: "clock.arrow.circlepath")
                .frame(maxWidth: .infinity, minHeight: 48)
            }.buttonStyle(SecondaryButtonStyle())
            Text("行程保存在本机，历史记录会一直保留，直到你删除。").font(.system(size: 11)).foregroundStyle(VIATheme.muted)
            Spacer(minLength: 0)
          }
        }.padding(.horizontal, 24).padding(.top, 45).padding(.bottom, 16)
          .frame(minHeight: geometry.size.height).frame(maxWidth: 700).frame(maxWidth: .infinity)
      }
    }.viaBackground().toolbar(.hidden, for: .navigationBar).refreshable { await store.refresh() }
  }
  private func homeArrival(_ state: ActivityState, journey: Journey) -> String {
    let riding = state.phase == .riding || state.phase == .completed
    let zone = (riding ? journey.currentLeg?.alighting?.timeZone : journey.currentLeg?.boarding?.timeZone)
      ?? "America/Toronto"
    if state.phase == .completed { return "行程已完成 · 查看详情" }
    if state.phase == .beforeDeparture { return "计划 \(Time.format(state.targetDate, zone: zone)) 出门" }
    let delay = Int((state.targetEpoch - state.scheduledEpoch) / 60)
    return "\(state.targetIsEstimate ? "预计" : "计划") \(Time.format(state.targetDate, zone: zone)) \(riding ? "到达" : "发车")"
      + (state.targetIsEstimate && delay > 0 ? " · 晚点 \(delay) 分钟" : "")
  }
  @ViewBuilder private func homeCard(_ journey: Journey, now: Date) -> some View {
    let j = Projection.resolvedJourney(journey, now: now)
    if let state = Projection.state(j, now: now) {
      VIACard(tinted: true, spacing: 0) {
        HStack {
          Text(j.legs.map { "VIA \($0.trainNumber)" }.joined(separator: " + ")).font(
            .system(size: 12, weight: .semibold))
          Spacer()
          StatusPill(title: Projection.isUpcoming(j, now: now) ? "待出发" : state.phase.title)
        }
        VStack(alignment: .leading, spacing: 2) {
          Text(j.legs.first?.boarding?.name ?? state.origin)
          if j.legs.count > 1 {
            let transfer = Text("经 \(j.legs[0].alighting?.name ?? "")")
              .foregroundStyle(VIATheme.muted)
            Text("\(transfer)  → \(j.legs.last?.alighting?.name ?? state.destination)")
          } else {
            Text("→ \(state.destination)")
          }
        }.font(.system(size: 27, weight: .semibold)).tracking(-0.7).padding(.top, 19)
        VIADivider().padding(.vertical, 19)
        if Projection.isUpcoming(j, now: now) {
          UpcomingSummary(journey: j, now: now)
        } else {
          Text(state.countdownLabel).font(.system(size: 12)).foregroundStyle(VIATheme.accent)
          CountdownText(state: state, now: now, frozen: store.qaScenario != nil, compact: true)
            .font(.system(size: 53, weight: .regular)).tracking(-2.5).minimumScaleFactor(0.6)
            .lineLimit(1).padding(.vertical, 5)
          HStack {
            Text(homeArrival(state, journey: j))
            Spacer()
            Image(systemName: "chevron.right")
          }.font(.system(size: 12)).foregroundStyle(VIATheme.amber)
        }
        if let next = state.nextTrainNumber, let epoch = state.nextDepartureEpoch,
          j.legs.indices.contains(j.currentLegIndex + 1) {
          VStack(alignment: .leading, spacing: 5) {
            Text("下一段 VIA \(next) · \(Time.format(Date(timeIntervalSince1970: epoch), zone: j.legs[j.currentLegIndex + 1].boarding?.timeZone ?? "America/Toronto")) 发车")
            if let summary = state.connectionSummary { Text(summary).fontWeight(.semibold) }
          }.font(.system(size: 11)).foregroundStyle(VIATheme.accent)
            .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            .background(VIATheme.surface, in: RoundedRectangle(cornerRadius: 12)).padding(.top, 19)
        }
      }
    }
  }
}
struct SavedJourneyCard: View {
  var journey: Journey
  var now: Date
  var body: some View {
    let state = Projection.state(journey, now: now)
    VIACard(padding: 17) {
      HStack {
        Text(journey.legs.map { "VIA \($0.trainNumber)" }.joined(separator: " + "))
          .font(.system(size: 12, weight: .semibold))
        Spacer()
        StatusPill(title: journey.trackingEnded ? "已结束追踪"
          : Projection.isUpcoming(journey, now: now) ? "待出发" : state?.phase.title ?? "待出发")
      }
      Text(journey.displayTitle).font(.system(size: 18, weight: .semibold))
      HStack {
        Text(Time.format(journey.legs.first?.boarding?.departure?.scheduledDate,
          zone: journey.legs.first?.boarding?.timeZone ?? "America/Toronto", date: true))
          .foregroundStyle(VIATheme.muted)
        Spacer()
        Image(systemName: "chevron.right").foregroundStyle(VIATheme.accent)
      }.font(.system(size: 12))
    }
  }
}
struct JourneyHistory: View {
  @Bindable var store: AppStore
  var showsBackButton = true
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 16) {
        if store.historyJourneys.isEmpty {
          ContentUnavailableView("还没有历史行程", systemImage: "clock.arrow.circlepath",
            description: Text("完成的行程会自动收进这里。"))
        } else {
          Text("共 \(store.historyJourneys.count) 趟 · 保存在本机")
            .font(.caption).foregroundStyle(VIATheme.muted)
          ForEach(store.historyJourneys) { journey in
            NavigationLink {
              JourneyDetail(store: store, id: journey.id, showsBackButton: true)
            } label: {
              SavedJourneyCard(journey: journey, now: store.qaDate ?? store.clockNow)
            }.buttonStyle(.plain)
          }
        }
      }.padding(24).frame(maxWidth: 800).frame(maxWidth: .infinity)
    }.viaBackground().toolbar(.hidden, for: .navigationBar)
      .safeAreaInset(edge: .top, spacing: 0) {
        VIANavigationBar(title: "历史行程", back: showsBackButton ? "返回" : "", onBack: { dismiss() }) { EmptyView() }
      }
  }
}
struct TrainBrowser: View {
  @Bindable var store: AppStore
  @State private var query = ""
  @State private var searchIndex = TrainSearchIndex(trains: [])
  @State private var filteredTrains: [TrainSnapshot] = []
  @State private var indexing = true
  @State private var selectedDate: String?
  private var availableDates: [String] { Array(Set(store.trains.map(\.originServiceDate))).sorted(by: >) }
  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 16) {
        if let message = store.sourceMessage { Notice(text: message) }
        if store.trains.isEmpty && !store.isRefreshing {
          ContentUnavailableView(
            "暂无列车数据", systemImage: "tram", description: Text("联网后下拉刷新。已保存行程仍可离线查看。"))
        }
        if !indexing && !store.trains.isEmpty && filteredTrains.isEmpty {
          ContentUnavailableView.search(text: query)
          Button("显示全部车次") { query = ""; selectedDate = nil }.buttonStyle(SecondaryButtonStyle())
        }
        if store.trains.isEmpty && store.isRefreshing {
          ProgressView("正在获取列车…").frame(maxWidth: .infinity)
        }
        if indexing && !store.trains.isEmpty { ProgressView("正在整理列车…") }
        ForEach(filteredTrains) { train in
          NavigationLink {
            TrainInfo(store: store, train: train)
          } label: {
            TrainRow(train: train)
          }.buttonStyle(.plain)
        }
      }.padding(24).frame(maxWidth: 800).frame(maxWidth: .infinity)
    }.toolbar(.hidden, for: .navigationBar).viaBackground()
      .safeAreaInset(edge: .top, spacing: 0) {
        VStack(alignment: .leading, spacing: 17) {
          Text("列车列表").font(.system(size: 32, weight: .semibold)).tracking(-1.5)
          HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(VIATheme.muted)
            TextField("搜索车次号或车站", text: $query)
              .submitLabel(.search).autocorrectionDisabled().textInputAutocapitalization(.never)
            if !query.isEmpty {
              Button("清除搜索", systemImage: "xmark.circle.fill") { query = "" }
                .labelStyle(.iconOnly).foregroundStyle(VIATheme.muted).frame(minWidth: 44, minHeight: 44)
            }
          }.font(.system(size: 14)).padding(13).background(
            VIATheme.line, in: RoundedRectangle(cornerRadius: 12))
          HStack {
            Menu {
              Picker("始发日期", selection: $selectedDate) {
                Text("全部日期").tag(String?.none)
                ForEach(availableDates, id: \.self) { date in
                  Text(date).tag(Optional(date))
                }
              }
            } label: {
              Label(selectedDate ?? "全部始发日期", systemImage: "calendar")
                .font(.system(size: 13, weight: .medium)).frame(minHeight: 44)
            }.accessibilityLabel("筛选始发日期，\(selectedDate ?? "全部日期")")
            Spacer()
            Text("\(filteredTrains.count) 班列车").font(.caption).foregroundStyle(VIATheme.muted)
          }
        }.padding(.horizontal, 24).padding(.top, 45).padding(.bottom, 12).background(
          VIATheme.background)
      }
      .task(id: store.trainDataRevision) {
        let snapshots = store.trains
        let previousIndex = searchIndex
        let work = Task.detached(priority: .userInitiated) { TrainSearchIndex(trains: snapshots, reusing: previousIndex) }
        let index = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
        guard !Task.isCancelled else { return }
        searchIndex = index
        filteredTrains = index.search(query, serviceDate: selectedDate)
        indexing = false
      }
      .task(id: query) {
        if !query.isEmpty {
          do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
        }
        guard !Task.isCancelled else { return }
        filteredTrains = searchIndex.search(query, serviceDate: selectedDate)
      }
      .onChange(of: selectedDate) { _, date in filteredTrains = searchIndex.search(query, serviceDate: date) }
      .scrollDismissesKeyboard(.interactively)
      .refreshable { await store.refresh() }.toolbar {
        ToolbarItemGroup(placement: .keyboard) {
          Spacer()
          Button("完成") {
            UIApplication.shared.sendAction(
              #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
          }
        }
      }
  }
}
struct TrainRow: View {
  var train: TrainSnapshot
  var selected: Bool? = nil
  var body: some View {
    VIACard(padding: 17, spacing: 13) {
      HStack {
        Label("VIA \(train.trainNumber)", systemImage: "tram.fill").font(
          .system(size: 12, weight: .semibold))
        Spacer()
        if let selected {
          Image(systemName: selected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 22)).foregroundStyle(selected ? VIATheme.yellow : VIATheme.line)
        } else {
          Text(train.originServiceDate).font(.system(size: 11)).foregroundStyle(VIATheme.muted)
        }
      }
      Text("\(train.calls.first?.name ?? train.from)  →  \(train.calls.last?.name ?? train.to)")
        .font(.system(size: 18, weight: .semibold)).tracking(-0.5)
      HStack(alignment: .lastTextBaseline) {
        Text(
          "\(Time.format(train.calls.first?.departure?.scheduledDate,zone:train.calls.first?.timeZone ?? "America/Toronto"))  —  \(Time.format(train.calls.last?.arrival?.scheduledDate,zone:train.calls.last?.timeZone ?? "America/Toronto"))"
        )
        .font(.system(size: 20)).monospacedDigit()
        Spacer()
        Text(arrivalSummary).font(.system(size: 10)).foregroundStyle(
          VIATheme.muted)
      }
    }
  }
  private var arrivalSummary: String {
    let zone = train.calls.last?.timeZone ?? "America/Toronto"
    if let arrival = train.calls.last?.arrival?.scheduledDate,
      Time.serviceDate(arrival, zone: zone) != train.originServiceDate {
      return "\(Time.formatted(arrival, zone: zone, pattern: "M月d日"))到达"
    }
    return train.arrived ? "已到达" : "计划时刻"
  }
}
struct TrainInfo: View {
  @Bindable var store: AppStore
  var train: TrainSnapshot
  @State private var adding = false
  @Environment(\.dismiss) private var dismiss
  private var currentTrain: TrainSnapshot {
    guard let latest = store.trains.first(where: { $0.id == train.id }),
      latest.version >= train.version else { return train }
    return latest
  }
  var body: some View {
    let snapshot = currentTrain
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        if let message = store.sourceMessage { Notice(text: message) }
        TrainRow(train: snapshot)
        TrainMap(train: snapshot, origin: snapshot.calls.first?.name ?? snapshot.from,
          destination: snapshot.calls.last?.name ?? snapshot.to,
          now: store.qaDate, isOffline: store.isOffline, height: 200)
        VIASectionLabel(title: "沿途站点", detail: "计划 / 预计")
        TimelineView(.periodic(from: .now, by: 30)) { context in
          StationTimeline(calls: snapshot.calls, boardingIndex: nil, alightingIndex: nil,
            now: store.qaDate ?? context.date, riding: snapshot.departed)
        }
        ForEach(Array(snapshot.alerts.enumerated()), id: \.offset) { _, alert in
          VIACard {
            Label(alert.title, systemImage: "info.circle").font(.headline)
            Text(alert.body).font(.subheadline)
            if let value = alert.url, let url = URL(string: value),
              ["https", "http"].contains(url.scheme ?? "") {
              Link("查看原始通知", destination: url)
            }
          }
        }
        Text("获取于 \(Time.format(Time.parse(snapshot.sourceFetchedAt), date: true))")
          .font(.caption).foregroundStyle(VIATheme.muted)
      }.padding(24).frame(maxWidth: 800).frame(maxWidth: .infinity)
    }.toolbar(.hidden, for: .navigationBar).viaBackground()
      .refreshable { await store.refresh() }
      .safeAreaInset(edge: .top, spacing: 0) {
        VIANavigationBar(title: "VIA \(snapshot.trainNumber)", back: "列车", onBack: { dismiss() }) {
          Button {
            Task { await store.refresh() }
          } label: {
            if store.isRefreshing { ProgressView() }
            else { Image(systemName: "arrow.clockwise") }
          }.frame(minWidth: 44, minHeight: 44).disabled(store.isRefreshing)
            .accessibilityLabel("刷新列车")
        }
      }
      .safeAreaInset(edge: .bottom, spacing: 0) {
        Button("添加到行程", systemImage: "plus") { adding = true }
          .buttonStyle(PrimaryButtonStyle()).padding(.horizontal, 24).padding(.vertical, 12)
          .frame(maxWidth: 800).frame(maxWidth: .infinity)
          .background(VIATheme.background).overlay(alignment: .top) { VIADivider() }
      }
      .sheet(isPresented: $adding) {
        AddJourneyFlow(store: store, initialTrain: currentTrain)
      }
  }
}
