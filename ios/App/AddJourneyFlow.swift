import SwiftUI
import TrackerCore

struct AddJourneyFlow: View {
  @Bindable var store: AppStore
  var initialTrain: TrainSnapshot?
  var initialJourney: Journey?
  @Environment(\.dismiss) private var dismiss
  @State private var step = 0
  @State private var query = ""
  @State private var date = Date()
  @State private var legs: [TrainLeg] = []
  @State private var selected: TrainSnapshot?
  @State private var selectedSource: ScheduleSource = .official
  @State private var referenceID: String?
  @State private var boarding: Int?
  @State private var alighting: Int?
  @State private var planning = Date()
  @State private var minutes = 30
  @State private var name = ""
  @State private var editingIndex: Int?
  @State private var error: String?
  @State private var picker: String?
  @State private var confirmPlanning = false
  @State private var ambiguousTrain: TrainSnapshot?
  private var serviceDate: String { Time.serviceDate(date) }
  private var connectionStation: String? { editingIndex == nil ? legs.last?.alightingCode : nil }
  private var candidates: [TrainSnapshot] {
    let groups = Dictionary(grouping: store.trains, by: \.trainNumber)
    return groups.values.compactMap { values in
      values.first { $0.originServiceDate == serviceDate }
        ?? values.sorted {
          abs(
            (Time.parse($0.originServiceDate + "T12:00:00-05:00") ?? .distantPast)
              .timeIntervalSince(date))
            < abs(
              (Time.parse($1.originServiceDate + "T12:00:00-05:00") ?? .distantPast)
                .timeIntervalSince(date))
        }.first
    }.filter { train in
      (query.isEmpty || train.trainNumber.localizedCaseInsensitiveContains(query)
        || train.calls.contains { $0.name.localizedCaseInsensitiveContains(query) })
        && canConnect(train)
    }.sorted { (Int($0.trainNumber) ?? 0) < (Int($1.trainNumber) ?? 0) }
  }
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          HStack {
            Text(step == 3 ? "确认行程" : "添加行程 · \(min(step+1,3))/3").font(.caption).foregroundStyle(
              .secondary)
            Spacer()
            if step < 3 {
              ProgressView(value: Double(step + 1), total: 3).frame(width: 90).tint(VIATheme.yellow)
            }
          }
          if step == 0 {
            searchStep
          } else if step == 1 {
            stationStep
          } else if step == 2 {
            planningStep
          } else {
            reviewStep
          }
        }.padding(24).frame(maxWidth: 700).frame(maxWidth: .infinity)
      }.viaBackground()
        .navigationTitle(initialJourney == nil ? "添加行程" : "编辑行程").navigationBarTitleDisplayMode(
          .inline
        )
        .toolbar {
          ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
          if step > 0 { ToolbarItem(placement: .topBarLeading) { Button("返回") { back() } } }
          ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("完成") {
              UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
          }
        }
        .sheet(item: Binding(get: { picker.map { PickerKind(id: $0) } }, set: { picker = $0?.id }))
      { kind in stationPicker(kind.id) }
        .alert("无法继续", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } }))
      {
        Button("好", role: .cancel) {}
      } message: {
        Text(error ?? "")
      }
        .confirmationDialog("调整可能与官方时刻不符", isPresented: $confirmPlanning, titleVisibility: .visible)
      {
        Button("使用我的规划时间") { commitLeg() }
      } message: {
        Text("此修改只影响计划出门，不会改变官方时刻。")
      }
        .confirmationDialog(
          "夏令时重复时刻",
          isPresented: Binding(
            get: { ambiguousTrain != nil }, set: { if !$0 { ambiguousTrain = nil } }),
          titleVisibility: .visible
        ) {
          Button("使用较早的一次") {
            if let train = ambiguousTrain { pick(train, repeatedTime: .first) }
            ambiguousTrain = nil
          }
          Button("使用较晚的一次") {
            if let train = ambiguousTrain { pick(train, repeatedTime: .last) }
            ambiguousTrain = nil
          }
        } message: {
          Text("目标日期的部分站点时刻出现两次，请确认参考时刻映射。不存在的时刻仍无法借用。")
        }
        .task {
          if let j = initialJourney {
            legs = j.legs
            minutes = j.travelToStationMinutes
            name = j.title
            step = 3
          } else if let initialTrain {
            date = Time.parse(initialTrain.originServiceDate + "T12:00:00-05:00") ?? date
            pick(initialTrain)
          }
          if let scenario = store.qaScenario { configurePreview(scenario) }
          if store.trains.isEmpty { await store.refresh() }
        }
    }
  }
  private var searchStep: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text(connectionStation == nil ? "选择列车" : "添加同站换乘").font(.largeTitle.bold())
      Text("选择列车始发服务日期；中途站上车日期将在区间内单独显示。").font(.subheadline).foregroundStyle(.secondary)
      DatePicker("始发服务日期", selection: $date, displayedComponents: .date).datePickerStyle(.compact)
        .environment(\.timeZone, TimeZone(identifier: "America/Toronto")!)
      TextField("搜索车次号或车站", text: $query).textFieldStyle(.roundedBorder).submitLabel(.done)
      if let connectionStation {
        Notice(
          text: "下一段上车站固定为 \(legs.last?.alighting?.name ?? connectionStation)，仅支持同站换乘。",
          symbol: "arrow.triangle.branch")
      }
      if let message = store.sourceMessage { Notice(text: message) }
      if candidates.isEmpty {
        ContentUnavailableView(
          connectionStation == nil ? "暂无可用班次" : "暂无同站可接续班次", systemImage: "tram",
          description: Text("可更换日期；缺少参考车次时无法生成时刻。"))
        Button("刷新列车数据") { Task { await store.refresh() } }
      }
      ForEach(candidates) { train in
        Button {
          pick(train)
        } label: {
          VStack(alignment: .leading, spacing: 8) {
            TrainRow(train: train)
            if train.originServiceDate != serviceDate {
              Text("参考时刻，待同步 · 参考实例 \(train.originServiceDate)").font(.caption).foregroundStyle(
                VIATheme.accent
              ).padding(.horizontal, 20)
            }
          }
        }.buttonStyle(.plain).accessibilityIdentifier("candidate-\(train.id)")
      }
    }
  }
  private var stationStep: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text("选择乘车区间").font(.largeTitle.bold())
      if let selected {
        Text("VIA \(selected.trainNumber) · \(selected.originServiceDate)").foregroundStyle(
          .secondary)
        if selectedSource == .reference { Notice(text: "仅借用计划时刻，不代表目标日期一定开行。") }
        Button("重新选择列车") { step = 0 }
        VIACard {
          Button {
            if connectionStation == nil { picker = "boarding" }
          } label: {
            stationField(
              "上车站", call: selected.calls.first { $0.index == boarding }, event: \.departure)
          }.buttonStyle(.plain).disabled(connectionStation != nil).accessibilityIdentifier(
            "boarding-station")
          Divider()
          Button {
            picker = "alighting"
          } label: {
            stationField(
              "下车站", call: selected.calls.first { $0.index == alighting }, event: \.arrival)
          }.buttonStyle(.plain).accessibilityIdentifier("alighting-station")
        }
        Button("下一步") {
          if let b = selected.calls.first(where: { $0.index == boarding }),
            let dep = b.departure?.scheduledDate
          {
            if editingIndex == nil { planning = dep }
            step = 2
          }
        }.buttonStyle(PrimaryButtonStyle()).disabled(boarding == nil || alighting == nil)
          .accessibilityIdentifier("next-stations")
      }
    }
  }
  private func stationField(
    _ title: String, call: StationCall?, event: KeyPath<StationCall, EventTime?>
  ) -> some View {
    HStack {
      VStack(alignment: .leading, spacing: 5) {
        Text(title).font(.caption).foregroundStyle(.secondary)
        Text(call?.name ?? "请选择").font(.headline)
        Text(
          Time.format(
            call?[keyPath: event]?.scheduledDate, zone: call?.timeZone ?? "America/Toronto",
            date: true)
        ).font(.subheadline.monospacedDigit())
      }
      Spacer()
      Image(systemName: "chevron.right")
    }.frame(minHeight: 60).contentShape(Rectangle())
  }
  private var planningStep: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text("规划出发时间").font(.largeTitle.bold())
      Text("规划时间由你设置，仅用于计算计划出门。延误不会自动推迟你的安排。").foregroundStyle(.secondary)
      VIACard {
        DatePicker("规划发车", selection: $planning, displayedComponents: [.date, .hourAndMinute])
          .environment(
            \.timeZone,
            TimeZone(
              identifier: selected?.calls.first { $0.index == boarding }?.timeZone
                ?? "America/Toronto")!)
        if legs.isEmpty || editingIndex == 0 {
          Stepper(value: $minutes, in: 0...1440, step: 15) { Text("前往车站 \(minutes) 分钟") }
        }
      }
      if legs.isEmpty || editingIndex == 0 {
        VIACard(tinted: true) {
          Text("计划出门").font(.subheadline)
          Text(
            Time.format(
              planning.addingTimeInterval(-Double(minutes * 60)),
              zone: selected?.calls.first { $0.index == boarding }?.timeZone ?? "America/Toronto",
              date: true)
          ).font(.largeTitle.monospacedDigit())
        }
      }
      Button("确认车段") {
        let official = selected?.calls.first { $0.index == boarding }?.departure?.scheduledDate
        if selectedSource == .official, let official,
          abs(official.timeIntervalSince(planning)) >= 60
        {
          confirmPlanning = true
        } else {
          commitLeg()
        }
      }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("confirm-leg")
    }
  }
  private var reviewStep: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text("确认完整行程").font(.largeTitle.bold())
      TextField("行程名称（可选）", text: $name).textFieldStyle(.roundedBorder)
      ForEach(Array(legs.enumerated()), id: \.element.id) { i, leg in
        VIACard {
          HStack {
            Text("第 \(i+1) 段 · VIA \(leg.trainNumber)").font(.headline)
            Spacer()
            Button("修改") {
              editingIndex = i
              selected = leg.snapshot
              selectedSource = leg.source
              referenceID = leg.referenceInstanceID
              boarding = leg.boardingIndex
              alighting = leg.alightingIndex
              planning = Date(timeIntervalSince1970: leg.planningDeparture)
              step = 1
            }
          }
          Text("\(leg.boarding?.name ?? "") → \(leg.alighting?.name ?? "")").font(.title3)
          Text(
            "\(Time.format(leg.boarding?.departure?.scheduledDate,zone:leg.boarding?.timeZone ?? "America/Toronto",date:true)) — \(Time.format(leg.alighting?.arrival?.scheduledDate,zone:leg.alighting?.timeZone ?? "America/Toronto",date:true))"
          ).font(.subheadline)
          if leg.source == .reference {
            Text("参考时刻 · 待同步").font(.caption).foregroundStyle(VIATheme.accent)
          }
          if i > 0, let previous = legs[i - 1].alighting?.arrival?.effectiveDate,
            let departure = leg.boarding?.departure?.scheduledDate
          {
            Text("同站接续间隔 \(Int(departure.timeIntervalSince(previous)/60)) 分钟").font(.caption)
          }
          if i == legs.count - 1 && legs.count > 1 {
            Button("移除末段", role: .destructive) { legs.removeLast() }
          }
        }
      }
      Button("添加同站换乘", systemImage: "plus") {
        editingIndex = nil
        query = ""
        if let last = legs.last?.alighting?.arrival?.scheduledDate { date = last }
        step = 0
      }.frame(minHeight: 44).disabled(legs.count >= 16)
      if let first = legs.first {
        Text(
          "计划出门 \(Time.format(Date(timeIntervalSince1970:first.planningDeparture-Double(minutes*60)),zone:first.boarding?.timeZone ?? "America/Toronto",date:true)) · 前往车站 \(minutes) 分钟"
        ).font(.subheadline).foregroundStyle(.secondary)
      }
      Button(initialJourney == nil ? "保存行程" : "保存修改") { save() }.buttonStyle(PrimaryButtonStyle())
        .disabled(legs.isEmpty).accessibilityIdentifier("save-journey")
    }
  }
  private func pick(_ train: TrainSnapshot, repeatedTime: ReferenceSchedule.RepeatedTime? = nil) {
    do {
      selectedSource = train.originServiceDate == serviceDate ? .official : .reference
      referenceID = selectedSource == .reference ? train.id : nil
      let snapshot =
        selectedSource == .reference
        ? try ReferenceSchedule.migrate(train, to: serviceDate, repeatedTime: repeatedTime) : train
      let b = snapshot.calls.first {
        (connectionStation == nil || $0.code == connectionStation) && $0.departure != nil
          && $0.index < (snapshot.calls.last?.index ?? 0)
      }
      guard let b, let a = snapshot.calls.last(where: { $0.arrival != nil && $0.index > b.index })
      else { throw ReferenceError.missingStations }
      if let previous = legs.last?.alighting?.arrival?.scheduledDate, editingIndex == nil,
        let dep = b.departure?.scheduledDate, dep < previous
      {
        error = "此班次计划发车早于上一段计划到达，请更换日期或车次。"
        return
      }
      selected = snapshot
      boarding = b.index
      alighting = a.index
      step = 1
    } catch ReferenceError.ambiguousTime {
      if repeatedTime == nil {
        ambiguousTrain = train
      } else {
        error = "该日期包含不存在的夏令时时刻，请更换日期或等待正式时刻。"
      }
    } catch { self.error = error.localizedDescription }
  }
  private func canConnect(_ train: TrainSnapshot) -> Bool {
    guard let connectionStation else { return true }
    guard
      let snapshot = try?
        (train.originServiceDate == serviceDate
        ? train : ReferenceSchedule.migrate(train, to: serviceDate, repeatedTime: .first)),
      let previous = legs.last?.alighting?.arrival?.scheduledDate
    else { return false }
    return snapshot.calls.contains { call in
      call.code == connectionStation
        && (call.departure?.scheduledDate.map { $0 >= previous } ?? false)
        && snapshot.calls.contains { $0.index > call.index && $0.arrival != nil }
    }
  }
  private func commitLeg() {
    guard let selected, let b = selected.calls.first(where: { $0.index == boarding }),
      let a = selected.calls.first(where: { $0.index == alighting })
    else { return }
    var leg = TrainLeg(
      snapshot: selected, boarding: b, alighting: a, source: selectedSource,
      referenceInstanceID: referenceID)
    leg.planningDeparture = planning.timeIntervalSince1970.rounded(.down)
    if let i = editingIndex, legs.indices.contains(i) {
      leg.id = legs[i].id
      legs[i] = leg
    } else {
      legs.append(leg)
    }
    editingIndex = nil
    step = 3
  }
  private func back() {
    if step == 3, let i = legs.indices.last {
      let leg = legs[i]
      editingIndex = i
      selected = leg.snapshot
      selectedSource = leg.source
      referenceID = leg.referenceInstanceID
      boarding = leg.boardingIndex
      alighting = leg.alightingIndex
      planning = Date(timeIntervalSince1970: leg.planningDeparture)
      step = 2
    } else if step == 1 && editingIndex != nil {
      editingIndex = nil
      step = 3
    } else {
      step = max(0, step - 1)
    }
  }
  private func save() {
    for i in legs.indices.dropFirst() {
      if legs[i - 1].alightingCode != legs[i].boardingCode {
        error = "第 \(i+1) 段与上一段不是同站接续，请修改车段。"
        return
      }
    }
    var j = initialJourney ?? Journey(legs: legs)
    j.legs = legs
    j.travelToStationMinutes = minutes
    j.title = String(name.prefix(200))
    j.currentLegIndex = min(j.currentLegIndex, legs.count - 1)
    store.save(j)
    store.selectedJourneyID = j.id
    dismiss()
  }
  private struct PickerKind: Identifiable { var id: String }
  private func configurePreview(_ scenario: String) {
    guard let j = store.journeys.first, let leg = j.legs.first else { return }
    date = leg.boarding?.departure?.scheduledDate ?? Date()
    if ["review", "transfer-review", "edit", "ipad-create"].contains(scenario) {
      legs = j.legs
      step = 3
      return
    }
    if ["add-transfer", "transfer-unavailable"].contains(scenario) {
      legs = j.legs
      step = 0
      return
    }
    if !["search", "date"].contains(scenario) {
      selected = leg.snapshot
      boarding = leg.boardingIndex
      alighting = leg.alightingIndex
      planning = Date(timeIntervalSince1970: leg.planningDeparture)
      step = ["departure", "travel", "manual-warning"].contains(scenario) ? 2 : 1
      if scenario == "manual-warning" { confirmPlanning = true }
      if scenario == "boarding-picker" { picker = "boarding" }
      if scenario == "alighting-picker" { picker = "alighting" }
    }
  }
  private func stationPicker(_ kind: String) -> some View {
    NavigationStack {
      List(selected?.calls ?? []) { call in
        let allowed =
          kind == "boarding"
          ? call.departure != nil && call.index < (alighting ?? Int.max)
          : call.arrival != nil && call.index > (boarding ?? -1)
        Button {
          if kind == "boarding" {
            if boarding != call.index, let departure = call.departure?.scheduledDate {
              planning = departure
            }
            boarding = call.index
          } else {
            alighting = call.index
          }
          picker = nil
        } label: {
          HStack {
            VStack(alignment: .leading, spacing: 6) {
              Text(call.name).font(.headline)
              Text(
                Time.format(
                  (kind == "boarding" ? call.departure : call.arrival)?.scheduledDate,
                  zone: call.timeZone, date: true)
              ).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            if call.index == (kind == "boarding" ? boarding : alighting) {
              Image(systemName: "checkmark.circle.fill").foregroundStyle(VIATheme.accent)
            }
          }.padding(.vertical, 8)
        }.disabled(!allowed).accessibilityIdentifier("station-\(call.index)")
      }.navigationTitle(kind == "boarding" ? "选择上车站" : "选择下车站").toolbar {
        Button("完成") { picker = nil }
      }
    }.presentationDetents([.medium, .large])
  }
}
