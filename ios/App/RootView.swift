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
    .safeAreaInset(edge: .top, spacing: 0) {
      if store.isTestMode {
        Label("测试数据 · 不影响正式行程", systemImage: "wrench.and.screwdriver")
          .font(.caption.bold()).frame(maxWidth: .infinity).padding(8)
          .background(VIATheme.yellow).foregroundStyle(.black)
      }
    }
  }
  private var content: some View {
    Group {
      if sizeClass == .regular && store.qaScenario != "ipad-narrow" {
        HStack(spacing: 0) {
          VStack(alignment: .leading, spacing: 18) {
            Text("VIA Tracker").font(.system(size: 27, weight: .semibold)).padding(.horizontal, 10)
            ForEach(
              Array(
                [
                  ("journeys", "我的行程", "house.fill"), ("trains", "列车列表", "tram.fill"),
                  ("settings", "设置", "gearshape"),
                ].enumerated()), id: \.offset
            ) { _, item in
              Button {
                sidebar = item.0
              } label: {
                Label(item.1, systemImage: item.2).font(.system(size: 14, weight: .medium))
                  .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                  .background(
                    sidebar == item.0 ? VIATheme.tintSurface : .clear,
                    in: RoundedRectangle(cornerRadius: 12))
              }.buttonStyle(.plain)
            }
            VIADivider()
            Text("已保存的行程").font(.system(size: 11)).foregroundStyle(VIATheme.muted).padding(
              .horizontal, 12)
            ScrollView {
              VStack(spacing: 4) {
                ForEach(store.journeys) { j in
                  Button {
                    sidebar = j.id
                  } label: {
                    VStack(alignment: .leading, spacing: 7) {
                      Text(j.displayTitle).font(.system(size: 14, weight: .medium))
                      Text(j.legs.map { "VIA \($0.trainNumber)" }.joined(separator: " + "))
                        .font(.system(size: 11)).foregroundStyle(VIATheme.muted)
                    }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                      .background(
                        sidebar == j.id ? VIATheme.tintSurface : .clear,
                        in: RoundedRectangle(cornerRadius: 12))
                  }.buttonStyle(.plain)
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
            } else if sidebar == "trains" {
              TrainBrowser(store: store)
            } else if let j = store.journeys.first(where: { $0.id == sidebar }) {
              JourneyDetail(store: store, id: j.id)
            } else {
              JourneyHome(store: store, adding: $adding, onSelect: { sidebar = $0 })
            }
          }.id(sidebar)
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
      if let sidebar, !["journeys", "trains", "settings"].contains(sidebar), !ids.contains(sidebar) {
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
  private func open(_ url: URL) {
    guard url.scheme == "viatracker" else { return }
    adding = false
    compactNavigationID = UUID()
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
                TimelineView(.periodic(from: .now, by: 1)) { context in
                  homeCard(j, now: store.qaDate ?? context.date)
                }
              }.buttonStyle(.plain)
            }
            let others = store.journeys.filter { $0.id != store.primaryJourney?.id }
            if !others.isEmpty {
              VIASectionLabel(title: "接下来的行程")
              ForEach(others) { j in
                Button {
                  onSelect(j.id)
                } label: {
                  VIACard(padding: 17) {
                    HStack {
                      Text(j.legs.map { "VIA \($0.trainNumber)" }.joined(separator: " + ")).font(
                        .system(size: 12, weight: .semibold))
                      Spacer()
                      StatusPill(
                        title: Projection.state(j, now: store.qaDate ?? Date())?.phase == .completed ? "已到达" : j.trackingEnded ? "已结束追踪"
                          : j.currentLeg?.source == .reference ? "待同步"
                          : Projection.state(j, now: store.qaDate ?? Date())?.phase.title ?? "待出发",
                        warning: j.currentLeg?.source == .reference)
                    }
                    Text(j.displayTitle).font(.system(size: 18, weight: .semibold))
                    HStack {
                      Text(
                        Time.format(j.legs.first?.boarding?.departure?.scheduledDate,
                          zone: j.legs.first?.boarding?.timeZone ?? "America/Toronto", date: true)
                      ).foregroundStyle(VIATheme.muted)
                      Spacer()
                      Text("查看行程").foregroundStyle(VIATheme.accent)
                    }.font(.system(size: 12))
                  }
                }.buttonStyle(.plain)
              }
            }
            Text("默认突出最近的未完成行程 · 可切换主行程").font(.system(size: 10)).foregroundStyle(VIATheme.muted)
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
          StatusPill(title: state.phase.title)
        }
        VStack(alignment: .leading, spacing: 2) {
          Text(j.legs.first?.boarding?.name ?? state.origin)
          if j.legs.count > 1 {
            (Text("经 \(j.legs[0].alighting?.name ?? "")  ").foregroundColor(VIATheme.muted)
              + Text("→ \(j.legs.last?.alighting?.name ?? state.destination)"))
          } else {
            Text("→ \(state.destination)")
          }
        }.font(.system(size: 27, weight: .semibold)).tracking(-0.7).padding(.top, 19)
        VIADivider().padding(.vertical, 19)
        Text(state.countdownLabel).font(.system(size: 12)).foregroundStyle(VIATheme.accent)
        CountdownText(state: state, now: now, frozen: store.qaScenario != nil, compact: true)
          .font(.system(size: 53, weight: .regular)).tracking(-2.5).minimumScaleFactor(0.6)
          .lineLimit(1).padding(.vertical, 5)
        HStack {
          Text(homeArrival(state, journey: j))
          Spacer()
          Image(systemName: "chevron.right")
        }.font(.system(size: 12)).foregroundStyle(VIATheme.amber)
        if let next = state.nextTrainNumber, let epoch = state.nextDepartureEpoch,
          j.legs.indices.contains(j.currentLegIndex + 1) {
          HStack {
            Text("下一段 VIA \(next) · \(Time.format(Date(timeIntervalSince1970: epoch), zone: j.legs[j.currentLegIndex + 1].boarding?.timeZone ?? "America/Toronto")) 发车")
            Spacer()
            if let gap = state.connectionMinutes { Text("间隔 \(gap) 分钟").fontWeight(.semibold) }
          }.font(.system(size: 11)).foregroundStyle(VIATheme.accent).padding(12)
            .background(VIATheme.surface, in: RoundedRectangle(cornerRadius: 12)).padding(.top, 19)
        }
      }
    }
  }
}
struct TrainBrowser: View {
  @Bindable var store: AppStore
  @State private var query = ""
  @State private var searchIndex = TrainSearchIndex(trains: [])
  @State private var filteredTrains: [TrainSnapshot] = []
  @State private var indexing = true
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
          Button("清除搜索") { query = "" }.buttonStyle(SecondaryButtonStyle())
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
        }.padding(.horizontal, 24).padding(.top, 45).padding(.bottom, 12).background(
          VIATheme.background)
      }
      .task(id: store.trains) {
        let snapshots = store.trains
        let work = Task.detached(priority: .userInitiated) { TrainSearchIndex(trains: snapshots) }
        let index = await work.value
        guard !Task.isCancelled else { return }
        searchIndex = index
        filteredTrains = index.search(query)
        indexing = false
      }
      .task(id: query) {
        if !query.isEmpty {
          do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
        }
        guard !Task.isCancelled else { return }
        filteredTrains = searchIndex.search(query)
      }
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
        Text("始发 \(train.originServiceDate)").font(.system(size: 10)).foregroundStyle(
          VIATheme.muted)
      }
    }
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
