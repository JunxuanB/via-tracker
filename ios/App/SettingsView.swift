import SwiftUI
import TrackerCore

struct SettingsView: View {
  @Bindable var store: AppStore
  var body: some View {
    Form {
      Section("实时活动与通知") {
        LabeledContent("实时活动", value: store.activities.status)
        LabeledContent("普通通知", value: store.notificationStatus)
        Button("允许时刻匹配通知") { Task { await store.enableNotifications() } }
        Button("打开系统设置") {
          if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
          }
        }
        Text("实时活动和普通通知的系统权限分别控制。活动最多持续 8 小时，结束后请回到行程续开。").font(.caption).foregroundStyle(
          .secondary)
      }
      Section("显示") {
        Picker("外观", selection: $store.appearance) {
          Text("跟随系统").tag("system")
          Text("浅色").tag("light")
          Text("深色").tag("dark")
        }
      }
      Section("数据") {
        LabeledContent("连接状态", value: store.isOffline ? "离线" : "网络可用")
        LabeledContent("源数据状态", value: sourceStatus)
        LabeledContent(
          "最近获取", value: Time.format(store.feed?.sourceFetchedAt.flatMap(Time.parse), date: true))
        Button("立即刷新") { Task { await store.refresh() } }
        Text("行程与最近有效数据保存在本机。没有账号和跨设备同步；仅同站换乘，不提供购票或接续保证。").font(.caption).foregroundStyle(
          .secondary)
        Text("保存行程后，后台保存此安装的行程订阅和推送 token，用于时刻匹配与活动更新。结束追踪会取消该订阅。").font(.caption).foregroundStyle(
          .secondary)
        if let sync = store.syncError { Text(sync).font(.caption).foregroundStyle(.secondary) }
      }
      Section("关于") {
        LabeledContent("VIA Tracker", value: "1.0.0")
        Text("独立列车追踪工具，与 VIA Rail 无隶属关系。运行信息以运营方为准。").font(.caption).foregroundStyle(.secondary)
        Link("VIA Rail", destination: URL(string: "https://www.viarail.ca")!)
      }
      #if DEBUG
        if let diagnostics = store.diagnostics {
          Section("调试诊断") { Text(diagnostics).font(.caption) }
        }
      #endif
    }.scrollContentBackground(.hidden).viaBackground().navigationTitle("设置").task {
      await store.checkNotifications()
    }
  }
  private var sourceStatus: String {
    switch store.feed?.sourceStatus {
    case "healthy": "正常"
    case "stale": "数据较旧"
    case "unavailable": "暂时无法更新"
    default: "尚未获取"
    }
  }
}
