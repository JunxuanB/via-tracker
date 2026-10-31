import SwiftUI
import TrackerCore

struct RootView: View {
  @Bindable var store: AppStore
  @Environment(\.horizontalSizeClass) private var sizeClass
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.dynamicTypeSize) private var userTypeSize
  @State private var tab = 0
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
  }
  private var content: some View {
    Group {
      if sizeClass == .regular && store.qaScenario != "ipad-narrow" {
        NavigationSplitView {
          List(selection: $sidebar) {
            Section("VIA Tracker") {
              Label("我的行程", systemImage: "house.fill").tag("journeys")
              Label("列车列表", systemImage: "tram.fill").tag("trains")
              Label("设置", systemImage: "gearshape").tag("settings")
            }
            Section("已保存的行程") {
              ForEach(store.journeys) { j in Label(j.displayTitle, systemImage: "tram").tag(j.id) }
            }
          }.navigationTitle("VIA Tracker").toolbar {
            Button("添加行程", systemImage: "plus") { adding = true }
          }
        } detail: {
          NavigationStack {
            if sidebar == "settings" {
              SettingsView(store: store)
            } else if sidebar == "trains" {
              TrainBrowser(store: store, onSelect: { _ in adding = true })
            } else if let j = store.journeys.first(where: { $0.id == sidebar }) {
              JourneyDetail(store: store, id: j.id)
            } else {
              JourneyHome(store: store, adding: $adding, onSelect: { sidebar = $0 })
            }
          }
        }
      } else {
        TabView(selection: $tab) {
          Tab("行程", systemImage: "house.fill", value: 0) {
            NavigationStack {
              JourneyHome(store: store, adding: $adding, onSelect: { store.selectedJourneyID = $0 })
                .navigationDestination(item: $store.selectedJourneyID) { id in
                  JourneyDetail(store: store, id: id)
                }
            }
          }
          Tab("列车", systemImage: "tram.fill", value: 1) {
            NavigationStack { TrainBrowser(store: store, onSelect: { _ in adding = true }) }
          }
          Tab("设置", systemImage: "gearshape", value: 2) {
            NavigationStack { SettingsView(store: store) }
          }
        }
      }
    }.viaBackground().preferredColorScheme(
      store.appearance == "dark" ? .dark : store.appearance == "light" ? .light : nil
    )
    .safeAreaInset(edge: .bottom) {
      if store.qaScenario != nil {
        Text("演示数据 · 原生验收模式").font(.caption2).foregroundStyle(.secondary)
          .dynamicTypeSize(.large)
      }
    }
    .sheet(isPresented: $adding) { AddJourneyFlow(store: store) }
    .onOpenURL { url in
      guard url.scheme == "viatracker" else { return }
      if url.host == "settings" {
        tab = 2
        sidebar = "settings"
      } else if url.host == "trains" {
        tab = 1
        sidebar = "trains"
      } else if url.host == "journey" {
        store.selectedJourneyID = url.lastPathComponent
        sidebar = url.lastPathComponent
        tab = 0
      }
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
      await store.checkNotifications()
      if store.notificationStatus == "已允许" && store.qaScenario == nil {
        UIApplication.shared.registerForRemoteNotifications()
      }
    }
    .onChange(of: scenePhase) { _, phase in
      store.foreground(phase == .active)
      if phase == .active {
        Task {
          await store.checkNotifications()
          if store.notificationStatus == "已允许" && store.qaScenario == nil {
            UIApplication.shared.registerForRemoteNotifications()
          }
        }
      }
    }
    .onChange(of: store.selectedJourneyID) { _, id in if let id { sidebar = id } }
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
}
struct JourneyHome: View {
  @Bindable var store: AppStore
  @Binding var adding: Bool
  var onSelect: (String) -> Void
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        if let message = store.sourceMessage {
          Notice(text: message, symbol: store.isOffline ? "wifi.slash" : "wifi.exclamationmark")
        }
        if store.journeys.isEmpty {
          ContentUnavailableView {
            Label("还没有行程", systemImage: "tram.fill")
          } description: {
            Text("添加列车，查看出门、乘车和换乘时间。\n支持离线查看最近的数据。")
          } actions: {
            Button("添加第一趟行程", systemImage: "plus") { adding = true }.buttonStyle(
              PrimaryButtonStyle())
          }.padding(.vertical, 60)
          Notice(text: "无需账号。行程保存在这台设备上。")
        } else {
          if let j = store.primaryJourney {
            HStack {
              Text("当前行程").font(.headline)
              Spacer()
              StatusPill(title: "主行程", symbol: "location.fill")
            }
            Button {
              onSelect(j.id)
            } label: {
              VStack(alignment: .leading, spacing: 14) {
                Text(j.displayTitle).font(.title2.bold())
                TimelineView(.periodic(from: .now, by: 1)) { context in
                  JourneyHero(
                    journey: j, now: store.qaDate ?? context.date, frozen: store.qaScenario != nil)
                }
              }
            }.buttonStyle(.plain)
          }
          Text("已保存的行程").font(.headline)
          ForEach(store.journeys) { j in
            Button {
              onSelect(j.id)
            } label: {
              VIACard {
                HStack {
                  Text(j.displayTitle).font(.headline)
                  Spacer()
                  Image(systemName: "chevron.right")
                }
                Text(j.legs.map { "VIA \($0.trainNumber)" }.joined(separator: " + ")).font(
                  .subheadline)
                Text(
                  "\(Time.format(j.legs.first?.boarding?.departure?.scheduledDate,date:true)) · \(j.completed ? "已完成":j.trackingEnded ? "已结束追踪":j.currentLeg?.source == .reference ? "参考时刻 · 待同步":"已保存")"
                ).font(.caption).foregroundStyle(.secondary)
              }
            }.buttonStyle(.plain)
          }
        }
        if let sync = store.syncError { Notice(text: sync, symbol: "arrow.triangle.2.circlepath") }
      }.padding(24).frame(maxWidth: 900).frame(maxWidth: .infinity)
    }.viaBackground().navigationTitle("我的行程").toolbar {
      Button("添加行程", systemImage: "plus") { adding = true }
    }.refreshable { await store.refresh() }
  }
}
struct TrainBrowser: View {
  @Bindable var store: AppStore
  var onSelect: (TrainSnapshot) -> Void
  @State private var query = ""
  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 16) {
        if let message = store.sourceMessage { Notice(text: message) }
        if store.trains.isEmpty {
          ContentUnavailableView(
            "暂无列车数据", systemImage: "tram", description: Text("联网后下拉刷新。已保存行程仍可离线查看。"))
        }
        ForEach(
          store.trains.filter {
            query.isEmpty || $0.trainNumber.localizedCaseInsensitiveContains(query)
              || $0.calls.contains { $0.name.localizedCaseInsensitiveContains(query) }
          }
        ) { train in
          NavigationLink {
            TrainInfo(store: store, train: train)
          } label: {
            TrainRow(train: train)
          }.buttonStyle(.plain)
        }
      }.padding(24).frame(maxWidth: 800).frame(maxWidth: .infinity)
    }.navigationTitle("列车列表").searchable(text: $query, prompt: "搜索车次号或车站").viaBackground()
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
  var body: some View {
    VIACard {
      HStack {
        Label("VIA \(train.trainNumber)", systemImage: "tram.fill").font(.headline)
        Spacer()
        Text(train.originServiceDate).font(.caption).foregroundStyle(.secondary)
      }
      Text("\(train.calls.first?.name ?? train.from) → \(train.calls.last?.name ?? train.to)").font(
        .title3.weight(.medium))
      Text(
        "\(Time.format(train.calls.first?.departure?.scheduledDate,zone:train.calls.first?.timeZone ?? "America/Toronto")) — \(Time.format(train.calls.last?.arrival?.scheduledDate,zone:train.calls.last?.timeZone ?? "America/Toronto",date:true))"
      ).font(.subheadline.monospacedDigit())
      Text("始发服务日期 · 站点以当前可用数据为准").font(.caption).foregroundStyle(.secondary)
    }
  }
}
struct TrainInfo: View {
  @Bindable var store: AppStore
  var train: TrainSnapshot
  @State private var adding = false
  var body: some View {
    ScrollView {
      VStack(spacing: 20) {
        TrainRow(train: train)
        StationTimeline(calls: train.calls, boardingIndex: nil, alightingIndex: nil)
        Button("添加到行程", systemImage: "plus") { adding = true }.buttonStyle(PrimaryButtonStyle())
      }.padding(24)
    }.navigationTitle("VIA \(train.trainNumber)").viaBackground().sheet(isPresented: $adding) {
      AddJourneyFlow(store: store, initialTrain: train)
    }
  }
}
