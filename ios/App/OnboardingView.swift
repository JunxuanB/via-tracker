import SwiftUI

// UserDefaults belongs to the app installation, rather than either data environment.
enum InstallationOnboarding {
  static var completionKey: String {
    #if DEBUG
      if let id = ProcessInfo.processInfo.environment["VIA_QA_ONBOARDING_ID"] {
        return "installation-onboarding.qa.\(id)"
      }
    #endif
    return "installation-onboarding.completed"
  }
  static var bypassForPreview: Bool {
    #if DEBUG
      return ProcessInfo.processInfo.environment["VIA_QA_SCENARIO"] != nil
        && ProcessInfo.processInfo.environment["VIA_QA_ONBOARDING_ID"] == nil
    #else
      return false
    #endif
  }
}

struct ProductDeclaration: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      declaration("独立开发 · 非官方产品", symbol: "info.circle", text:
        "本产品不是由 VIA Canada（VIA Rail Canada）开发。我们调用 VIA Canada 的官方公开 API 获取信息。")
      declaration("开放源码", symbol: "chevron.left.forwardslash.chevron.right", text:
        "本程序是开源的，现阶段免费。未来若使用人数增加，可能会收取少量费用，用于服务器运行、服务扩容和代码维护。如果你不希望付费，欢迎使用开源版自行部署。")
      declaration("致 VIA 代表", symbol: "envelope", text:
        "如果你是 VIA 代表，并不希望该程序公开，请通过下方项目页面与我们联系。")
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 24) { projectLinks }
        VStack(alignment: .leading, spacing: 4) { projectLinks }
      }
    }
  }
  private var projectLinks: some View {
    Group {
      Link("查看开源项目 ↗", destination: URL(string: "https://github.com/JunxuanB/via-tracker")!)
      Link("联系我们 ↗", destination: URL(string: "https://github.com/JunxuanB/via-tracker/issues")!)
    }.font(.subheadline.weight(.medium)).frame(minHeight: 44)
  }
  private func declaration(_ title: String, symbol: String, text: String) -> some View {
    VIACard(spacing: 10) {
      Label(title, systemImage: symbol).font(.headline).foregroundStyle(VIATheme.accent)
      Text(text).font(.subheadline).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
    }
  }
}

struct OnboardingView: View {
  @Bindable var store: AppStore
  var onComplete: () -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  @State private var step = 0
  @State private var arrived = false
  @State private var requesting = false
  @State private var checkedPermissions = false

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          HStack {
            Text("TRAIN TRACKER").font(.caption.weight(.semibold)).tracking(2)
            Spacer()
            Text("\(step + 1) / 2").font(.caption.monospacedDigit())
              .accessibilityLabel("第 \(step + 1) 步，共两步")
          }.foregroundStyle(VIATheme.muted).id("onboarding-top")
          hero
          VStack(alignment: .leading, spacing: 10) {
            Text(step == 0 ? "欢迎搭乘\nTrain Tracker" : "让行程提醒\n及时抵达")
              .font(.largeTitle.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
              .accessibilityAddTraits(.isHeader)
            Text(step == 0 ? "出发之前，先了解我们。" : "由你决定如何接收提醒，稍后也能在设置中修改。")
              .font(.subheadline).foregroundStyle(VIATheme.muted)
          }
          Group {
            if step == 0 {
              ProductDeclaration()
            } else {
              permissions
            }
          }.id(step).transition(.opacity.combined(with: .offset(x: reduceMotion ? 0 : 20)))
          VStack(spacing: 8) {
            Button(step == 0 ? "我已了解，继续" : "开始使用") {
              if step == 0 {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { step = 1 }
              } else {
                onComplete()
              }
            }.buttonStyle(PrimaryButtonStyle())
              .accessibilityIdentifier(step == 0 ? "onboarding-next" : "onboarding-finish")
              .disabled(requesting)
            if step == 1 {
              Text("权限可选，不开启也能查看和保存行程。")
                .font(.caption).foregroundStyle(VIATheme.muted).multilineTextAlignment(.center)
              Button("返回声明") {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { step = 0 }
              }.font(.subheadline).frame(minHeight: 44).disabled(requesting)
            }
          }
        }.padding(24).frame(maxWidth: 620).frame(maxWidth: .infinity)
      }.viaBackground()
        .onChange(of: step) { _, _ in proxy.scrollTo("onboarding-top", anchor: .top) }
        .task {
          withAnimation(reduceMotion ? nil : .spring(duration: 0.8, bounce: 0.2)) { arrived = true }
          await refreshPermissions()
        }
        .onChange(of: scenePhase) { _, phase in
          if phase == .active { Task { await refreshPermissions() } }
        }
    }
  }

  private var hero: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 26).fill(VIATheme.tintSurface)
      HStack(spacing: 8) {
        Circle().fill(VIATheme.accent).frame(width: 8, height: 8)
        Rectangle().fill(VIATheme.accent.opacity(0.25)).frame(height: 2)
        Image(systemName: step == 0 ? "tram.fill" : "bell.badge.fill")
          .font(.system(size: 42)).foregroundStyle(VIATheme.accent)
          .frame(width: 80, height: 80)
          .background(VIATheme.surface, in: RoundedRectangle(cornerRadius: 22))
          .offset(x: arrived ? 0 : -65).opacity(arrived ? 1 : 0)
        Rectangle().fill(VIATheme.accent.opacity(0.25)).frame(height: 2)
        Circle().strokeBorder(VIATheme.accent, lineWidth: 2).frame(width: 12, height: 12)
      }.padding(24)
    }.frame(height: 130).accessibilityHidden(true)
  }

  private var permissions: some View {
    VStack(spacing: 16) {
      VIACard(spacing: 12) {
        Label("行程通知", systemImage: "bell.badge").font(.headline)
        Text("接收出门、发车、换乘和到达提醒。").font(.subheadline).foregroundStyle(VIATheme.muted)
        Text(checkedPermissions ? store.notificationStatus : "正在检查…").font(.caption)
          .foregroundStyle(VIATheme.accent)
        Button(requesting ? "正在请求…" : store.notificationStatus == "尚未请求" ? "允许通知" : "管理通知权限") {
          Task {
            requesting = true
            defer { requesting = false }
            await store.checkNotifications()
            if store.notificationStatus == "尚未请求" {
              await store.enableNotifications()
            } else {
              openSettings()
            }
          }
        }.buttonStyle(SecondaryButtonStyle()).disabled(requesting || !checkedPermissions)
          .accessibilityIdentifier("onboarding-notifications")
      }
      VIACard(spacing: 12) {
        Label("实时活动", systemImage: "antenna.radiowaves.left.and.right").font(.headline)
        Text("在锁屏和支持的设备灵动岛上查看倒计时与行程进度。添加行程后，可按需开启实时活动。")
          .font(.subheadline).foregroundStyle(VIATheme.muted)
        Text(!checkedPermissions ? "正在检查…" : store.activities.enabled ? "系统已允许" : "系统未允许")
          .font(.caption).foregroundStyle(VIATheme.accent)
        Text("实时活动由系统管理；可在系统设置中管理实时活动及频繁更新权限。")
          .font(.caption).foregroundStyle(VIATheme.muted)
        Button("管理实时活动", action: openSettings).buttonStyle(SecondaryButtonStyle())
      }
    }
  }
  private func refreshPermissions() async {
    await store.checkNotifications()
    await store.activities.refreshAuthorization()
    checkedPermissions = true
  }
  private func openSettings() {
    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
  }
}
