import SwiftUI
import TrackerCore

struct SettingsView: View {
  @Bindable var store: AppStore
  @State private var dataDetails = false
  @State private var aboutDetails = false
  @State private var activityDetails = false
  @State private var appearanceDetails = false
  @State private var environmentDetails = false
  @State private var versionTaps = 0
  @State private var lastVersionTap = Date.distantPast
  @State private var testToolsExpanded = false
  @State private var copiedDeviceCode = false
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 17) {
        #if DEBUG
          if store.isTestMode { testModePanel }
        #endif
        Text(L10n.text("设置")).font(.system(size: 32, weight: .semibold)).tracking(-1.5)
        Text(L10n.text("管理显示、规划与数据。")).font(.system(size: 13)).foregroundStyle(VIATheme.muted)
        VIASectionLabel(title: L10n.text("实时活动"))
        group {
          Button {
            activityDetails = true
          } label: {
            row(
              L10n.text("实时活动"), value: store.activities.enabled ? L10n.text("系统已允许") : L10n.text("系统未允许"),
              symbol: "antenna.radiowaves.left.and.right")
          }
          VIADivider()
          Button {
            openSettings()
          } label: {
            row(
              L10n.text("频繁更新"), value: store.activities.frequentPushesEnabled ? L10n.text("系统已允许") : L10n.text("系统未允许"),
              symbol: "arrow.triangle.2.circlepath")
          }
          VIADivider()
          Button {
            notificationAction()
          } label: {
            row(L10n.text("通知权限"), value: store.notificationStatus, symbol: "bell")
          }
          VIADivider()
          Button {
            openSettings()
          } label: {
            row(L10n.text("系统设置"), value: L10n.text("权限管理"), symbol: "gearshape")
          }
        }
        VIASectionLabel(title: L10n.text("显示与规划"))
        group {
          Button {
            appearanceDetails = true
          } label: {
            row(
              L10n.text("外观"),
              value: store.appearance == "dark"
                ? L10n.text("深色") : store.appearance == "light" ? L10n.text("浅色") : L10n.text("跟随系统"), symbol: "moon")
          }
          VIADivider()
          row(L10n.text("车站时间"), value: L10n.text("当地时区"), symbol: "clock", chevron: false)
          VIADivider()
          row(L10n.text("前往耗时"), value: L10n.text("在行程中设置"), symbol: "figure.walk", chevron: false)
          VIADivider()
          row(L10n.text("默认主行程"), value: L10n.text("最近的未完成行程"), symbol: "location", chevron: false)
        }
        VIASectionLabel(title: L10n.text("数据"))
        group {
          Button {
            dataDetails = true
          } label: {
            row(L10n.text("离线数据"), value: store.journeys.isEmpty ? L10n.text("暂无保存的行程") : L10n.text("已缓存当前行程"), symbol: "wifi.slash")
          }
          VIADivider()
          Button {
            dataDetails = true
          } label: {
            row(L10n.text("数据来源"), value: store.isTestMode ? L10n.text("测试数据") : "VIA Rail", symbol: "info.circle")
          }
        }
        Button(L10n.text("关于 Train Tracker 与开源声明"), systemImage: "info.circle") {
          aboutDetails = true
        }.font(.subheadline).frame(minHeight: 44)
        // The environment switch is a development tool and is not compiled into release builds.
        #if DEBUG
          Button {
            let now = Date()
            versionTaps = now.timeIntervalSince(lastVersionTap) < 3 ? versionTaps + 1 : 1
            lastVersionTap = now
            if versionTaps >= 7 { versionTaps = 0; environmentDetails = true }
          } label: {
            versionLabel
          }.buttonStyle(.plain).padding(.top, 12).accessibilityLabel(L10n.text("版本号，连续点击七次打开环境选择"))
        #else
          versionLabel.padding(.top, 12)
        #endif
      }.padding(.horizontal, 24).padding(.top, 45).padding(.bottom, 20).frame(maxWidth: 700).frame(
        maxWidth: .infinity)
    }.viaBackground().toolbar(.hidden, for: .navigationBar)
      .task { await store.checkNotifications() }
      #if DEBUG
      .sheet(isPresented: $environmentDetails) { environmentSheet }
      #endif
      .sheet(isPresented: $aboutDetails) {
        NavigationStack {
          ScrollView { ProductDeclaration().padding(24).frame(maxWidth: 620).frame(maxWidth: .infinity) }
            .viaBackground().navigationTitle(L10n.text("关于 Train Tracker"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button(L10n.text("完成")) { aboutDetails = false } }
        }
      }

      .confirmationDialog(L10n.text("外观"), isPresented: $appearanceDetails, titleVisibility: .visible) {
        Button(L10n.text("跟随系统")) { store.appearance = "system" }
        Button(L10n.text("浅色")) { store.appearance = "light" }
        Button(L10n.text("深色")) { store.appearance = "dark" }
      }
      .sheet(isPresented: $activityDetails) {
        NavigationStack {
          ScrollView {
            VStack(alignment: .leading, spacing: 20) {
              Notice(text: L10n.text("出门、发车前 15 分钟、发车、换乘到站和最终到达会单独提醒。划掉实时活动不会关闭行程通知；结束追踪会停止提醒。"))
              Notice(text: L10n.text("提前保存的行程会在出门前 5 小时开始倒计时，并自动开启实时活动。"), symbol: "clock")
              LabeledContent(L10n.text("实时活动"), value: store.activities.status)
              LabeledContent(L10n.text("普通通知"), value: store.notificationStatus)
              Button(store.notificationStatus == L10n.text("尚未请求") ? L10n.text("允许行程通知") : L10n.text("管理通知权限")) { notificationAction() }.buttonStyle(
                SecondaryButtonStyle())
              Button(L10n.text("打开系统设置")) { openSettings() }.buttonStyle(PrimaryButtonStyle())
            }.padding(24)
          }.viaBackground().navigationTitle(L10n.text("实时活动与通知")).navigationBarTitleDisplayMode(.inline)
            .toolbar { Button(L10n.text("完成")) { activityDetails = false } }
        }.presentationDetents([.medium, .large])
      }
      .sheet(isPresented: $dataDetails) {
        NavigationStack {
          ScrollView {
            VStack(alignment: .leading, spacing: 20) {
              VIACard {
                LabeledContent(L10n.text("连接状态"), value: store.isOffline ? L10n.text("离线") : L10n.text("网络可用"))
                LabeledContent(L10n.text("源数据状态"), value: sourceStatus)
                LabeledContent(
                  L10n.text("最近获取"),
                  value: Time.format(store.feed?.sourceFetchedAt.flatMap(Time.parse), date: true))
              }
              Button(store.isRefreshing ? L10n.text("正在刷新…") : L10n.text("立即刷新")) { Task { await store.refresh() } }
                .buttonStyle(PrimaryButtonStyle()).disabled(store.isRefreshing)
              Text(L10n.text("行程与最近有效数据保存在本机。没有账号和跨设备同步；仅同站换乘，不提供购票或接续保证。"))
              Text(L10n.text("保存行程后，后台保存必要的行程与通知信息，用于时刻和实时活动更新。结束追踪即可停止该行程的更新。"))
              if let sync = store.syncError { Notice(text: sync) }
              Link("VIA Rail", destination: URL(string: "https://www.viarail.ca")!)
              #if DEBUG
                if let diagnostics = store.diagnostics { Text(diagnostics).font(.caption) }
              #endif
            }.font(.system(size: 13)).padding(24)
          }.viaBackground().navigationTitle(L10n.text("数据")).navigationBarTitleDisplayMode(.inline)
            .toolbar { Button(L10n.text("完成")) { dataDetails = false } }
        }.presentationDetents([.medium, .large])
      }
  }
  private var versionLabel: some View {
    Text(L10n.text("Train Tracker %@ · 非 VIA Rail 官方产品\\n无账号 · 行程保存在本机", String(describing: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")))
      .font(.system(size: 10)).lineSpacing(4).foregroundStyle(VIATheme.muted)
      .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
  }
  #if DEBUG
  private var testModePanel: some View {
    VIACard(tinted: true, padding: 16, spacing: 8) {
      HStack(spacing: 12) {
        Label(L10n.text("测试模式"), systemImage: "wrench.and.screwdriver").font(.subheadline.bold())
        Spacer(minLength: 4)
        Button(L10n.text("切换环境")) { environmentDetails = true }
          .font(.caption.weight(.medium)).frame(minHeight: 44)
      }
      Text(L10n.text("正式行程独立保存")).font(.caption).foregroundStyle(VIATheme.muted)
      DisclosureGroup(L10n.text("测试工具"), isExpanded: $testToolsExpanded) {
        VStack(alignment: .leading, spacing: 8) {
          Link(L10n.text("打开网页版测试台"), destination: store.configuration.baseURL).frame(minHeight: 44)
          ShareLink(item: store.configuration.baseURL) {
            Label(L10n.text("分享测试台链接"), systemImage: "square.and.arrow.up")
          }.frame(minHeight: 44)
          if let code = store.testDeviceCode {
            VStack(alignment: .leading, spacing: 4) {
              Text(L10n.text("本机编号")).font(.caption).foregroundStyle(VIATheme.muted)
              HStack {
                Text(code).monospaced().textSelection(.enabled).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                Button {
                  UIPasteboard.general.string = code
                  copiedDeviceCode = true
                } label: {
                  Label(copiedDeviceCode ? L10n.text("已复制") : L10n.text("复制"), systemImage: copiedDeviceCode ? "checkmark" : "doc.on.doc")
                    .fixedSize(horizontal: true, vertical: false)
                }.frame(minWidth: 44, minHeight: 44)
                  .accessibilityLabel(copiedDeviceCode ? L10n.text("本机编号已复制") : L10n.text("复制本机测试编号"))
              }
            }
          }
          Text(store.supportsRemotePush ? L10n.text("网页修改后可锁屏查看实时活动；按本机编号发送测试通知。") : L10n.text("本地测试仅在 App 前台刷新。"))
            .font(.caption).foregroundStyle(VIATheme.muted)
        }.font(.subheadline).padding(.top, 8)
      }.font(.subheadline)
    }.accessibilityIdentifier("settings-test-mode")
      .task(id: copiedDeviceCode) {
        guard copiedDeviceCode else { return }
        do { try await Task.sleep(for: .seconds(2)); copiedDeviceCode = false } catch {}
      }
  }
  private var environmentSheet: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          Text(L10n.text("选择 App 使用的数据环境。行程会分别保存，切换会关闭当前实时活动。")).font(.subheadline).foregroundStyle(.secondary)
          ForEach(AppEnvironment.allCases, id: \.self) { environment in
            HStack {
              Button {
                Task { await store.changeEnvironment?(environment) }
              } label: {
                HStack {
                  Image(systemName: store.configuration.environment == environment && !store.configuration.localOnly ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(VIATheme.accent)
                  Text(environment.title)
                  Spacer()
                }.frame(minHeight: 52).contentShape(Rectangle())
              }.buttonStyle(.plain)
              if environment == .test {
                NavigationLink {
                  testEnvironmentInfo
                } label: {
                  Image(systemName: "info.circle").frame(width: 44, height: 44)
                }.accessibilityLabel(L10n.text("测试环境说明与入口"))
              }
            }
            Divider()
          }
          if store.isSwitchingEnvironment { ProgressView(L10n.text("正在切换环境…")) }
          if let error = store.environmentError { Notice(text: error) }
        }.padding(24)
      }.viaBackground().navigationTitle(L10n.text("环境选择")).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.text("完成")) { environmentDetails = false } } }
        .disabled(store.isSwitchingEnvironment)
    }.presentationDetents([.medium, .large]).interactiveDismissDisabled(store.isSwitchingEnvironment)
  }
  private var testEnvironmentInfo: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Label(L10n.text("公网测试环境"), systemImage: "wrench.and.screwdriver").font(.title2.bold())
        Text(L10n.text("在网页中调整延误、到站和列车位置，再通过锁屏实时活动查看变化。也可以向本机发送一条测试通知。"))
        Text(L10n.text("面板公开且由测试设备共享；正式行程独立保存。测试模式会一直保留，直到你切回正式环境。"))
          .font(.subheadline).foregroundStyle(.secondary)
        Link(L10n.text("打开公网测试台"), destination: AppConfiguration.configuration(for: .test).baseURL)
          .frame(minHeight: 44)
        if let code = store.testDeviceCode {
          LabeledContent(L10n.text("本机测试编号"), value: code).textSelection(.enabled)
        }
        Button(store.isSwitchingEnvironment ? L10n.text("正在切换…") : L10n.text("进入测试环境")) {
          Task { await store.changeEnvironment?(.test) }
        }.buttonStyle(PrimaryButtonStyle()).disabled(store.isSwitchingEnvironment)
        if let error = store.environmentError { Notice(text: error) }
      }.padding(24)
    }.viaBackground().navigationTitle(L10n.text("测试环境")).navigationBarTitleDisplayMode(.inline)
  }
  #endif
  private func group<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    VStack(spacing: 0, content: content).padding(.horizontal, 16)
      .background(VIATheme.surface, in: RoundedRectangle(cornerRadius: 20)).buttonStyle(.plain)
  }
  private func row(_ title: String, value: String, symbol: String, chevron: Bool = true)
    -> some View
  {
    HStack(spacing: 12) {
      Image(systemName: symbol).foregroundStyle(VIATheme.accent).frame(width: 21)
      Text(title)
      Spacer(minLength: 4)
      Text(value).font(.system(size: 12)).foregroundStyle(VIATheme.muted)
      if chevron {
        Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(VIATheme.muted)
      }
    }.font(.system(size: 14)).frame(minHeight: 52).contentShape(Rectangle())
  }
  private func notificationAction() {
    if store.notificationStatus == L10n.text("未允许") || store.notificationStatus == L10n.text("已允许") {
      openSettings()
    } else {
      Task { await store.enableNotifications() }
    }
  }
  private func openSettings() {
    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
  }
  private var sourceStatus: String {
    switch store.feed?.sourceStatus {
    case "healthy": L10n.text("正常")
    case "stale": L10n.text("数据较旧")
    case "unavailable": L10n.text("暂时无法更新")
    default: L10n.text("尚未获取")
    }
  }
}
