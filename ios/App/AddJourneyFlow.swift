import SwiftUI
import TrackerCore

struct AddJourneyFlow: View {
  @Bindable var store: AppStore
  var initialTrain: TrainSnapshot?
  var initialJourney: Journey?
  @Environment(\.dismiss) private var dismiss
  @State private var initialized = false
  @State private var step = 0
  @State private var planningPart = 0
  @State private var chosenTrain: TrainSnapshot?
  @State private var notDepartedOnly = false
  @State private var startOnSave = true
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
  @State private var confirmDiscard = false
  @FocusState private var fieldFocused: Bool
  @State private var ambiguousTrain: TrainSnapshot?
  private var boardingZone: String {
    selected?.calls.first { $0.index == boarding }?.timeZone ?? "America/Toronto"
  }
  private var resolvedTrain: TrainSnapshot? {
    candidates.first { $0.id == chosenTrain?.id } ?? candidates.first
  }
  private var serviceDate: String { Time.serviceDate(date) }
  /// Saved further ahead than the tracking window: no countdown or Live Activity yet.
  private var savesAsUpcoming: Bool {
    guard let first = legs.first else { return false }
    return Date().timeIntervalSince1970
      < first.planningDeparture - Double(minutes * 60) - Journey.trackingLead
  }
  private var connectionStation: String? {
    if let index = editingIndex { return index > 0 ? legs[index - 1].alightingCode : nil }
    return legs.last?.alightingCode
  }
  private struct CandidateRequest: Hashable, Sendable {
    var revision: Int
    var active: Bool
    var date: String
    var previous: TrainLeg?
  }
  @State private var candidateIndex = TrainSearchIndex(trains: [])
  @State private var appliedQuery = ""
  @State private var matchingCandidates: [TrainSnapshot] = []
  @State private var indexing = true
  @State private var preparedRequest: CandidateRequest?
  private var candidateRequest: CandidateRequest {
    CandidateRequest(revision: store.trainDataRevision, active: step == 0 && (initialJourney == nil || initialized), date: serviceDate,
      previous: editingIndex == nil ? legs.last : nil)
  }
  private var candidates: [TrainSnapshot] {
    guard preparedRequest == candidateRequest else { return [] }
    return matchingCandidates.filter {
      !notDepartedOnly || $0.originServiceDate != serviceDate || !$0.departed
    }
  }
  var body: some View {
    NavigationStack {
      ScrollViewReader { proxy in
        ScrollView {
          VStack(alignment: .leading, spacing: 22) {
            if initialJourney == nil {
              HStack {
                Text(L10n.text("添加行程 · %@/3", String(describing: step == 3 ? 3 : step < 2 ? 1 : 2)))
                  .font(.caption).foregroundStyle(VIATheme.muted)
                Spacer()
                HStack(spacing: 5) {
                  ForEach(0..<3) { index in
                    Capsule().fill(index < (step < 2 ? 1 : step == 2 ? 2 : 3) ? VIATheme.yellow : VIATheme.line)
                      .frame(width: 18, height: 3)
                  }
                }.accessibilityHidden(true)
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
          }.padding(.horizontal, 24).padding(.vertical, 16).frame(maxWidth: 700).frame(
            maxWidth: .infinity).id("flow-top")
        }.viaBackground()
          .scrollDismissesKeyboard(.interactively)
          .onChange(of: step) { _, _ in
            fieldFocused = false
            proxy.scrollTo("flow-top", anchor: .top)
          }
          .onChange(of: planningPart) { _, _ in proxy.scrollTo("flow-top", anchor: .top) }
          .toolbar(.hidden, for: .navigationBar)
          .safeAreaInset(edge: .top, spacing: 0) {
            VIANavigationBar(
              title: initialJourney != nil && step == 3 ? L10n.text("编辑行程") : step == 0
                ? L10n.text("选择列车")
                : step == 1 ? L10n.text("乘车区间") : step == 2 ? (planningPart == 0 ? L10n.text("规划时间") : L10n.text("前往耗时")) : L10n.text("确认行程"),
              back: initialJourney != nil && step == 3 ? L10n.text("关闭") : step == 0 ? (legs.isEmpty ? L10n.text("取消") : L10n.text("返回")) : L10n.text("返回"),
              onBack: {
                if initialJourney != nil && step == 3 { requestCancel() }
                else if step == 0 && legs.isEmpty { requestCancel() }
                else if step == 0 { step = 3 }
                else { back() }
              }
            ) {
              if !(initialJourney != nil && step == 3) && (step > 0 || !legs.isEmpty) { Button(L10n.text("取消")) { requestCancel() } }
            }
          }
          .safeAreaInset(edge: .bottom, spacing: 0) { footer }
          .sheet(item: Binding(get: { picker.map { PickerKind(id: $0) } }, set: { picker = $0?.id }))
        { kind in stationPicker(kind.id) }
          .alert(L10n.text("无法继续"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } }))
        {
          Button(L10n.text("好"), role: .cancel) {}
        } message: {
          Text(error ?? "")
        }
          .confirmationDialog(L10n.text("放弃本次修改？"), isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button(L10n.text("放弃修改"), role: .destructive) { dismiss() }
            Button(L10n.text("继续编辑"), role: .cancel) {}
          } message: { Text(L10n.text("未保存的内容将丢失，已保存的行程不会改变。")) }
          .confirmationDialog(L10n.text("调整可能与官方时刻不符"), isPresented: $confirmPlanning, titleVisibility: .visible)
        {
          Button(L10n.text("使用我的规划时间")) { commitLeg() }
        } message: {
          Text(L10n.text("此修改只影响计划出门，不会改变官方时刻。"))
        }
          .confirmationDialog(
            L10n.text("夏令时重复时刻"),
            isPresented: Binding(
              get: { ambiguousTrain != nil }, set: { if !$0 { ambiguousTrain = nil } }),
            titleVisibility: .visible
          ) {
            Button(L10n.text("使用较早的一次")) {
              if let train = ambiguousTrain { pick(train, repeatedTime: .first) }
              ambiguousTrain = nil
            }
            Button(L10n.text("使用较晚的一次")) {
              if let train = ambiguousTrain { pick(train, repeatedTime: .last) }
              ambiguousTrain = nil
            }
          } message: {
            Text(L10n.text("目标日期的部分站点时刻出现两次，请确认参考时刻映射。不存在的时刻仍无法借用。"))
          }
          .task {
            guard !initialized else { return }
            initialized = true
            if let j = initialJourney {
              legs = j.legs
              minutes = j.travelToStationMinutes
              name = j.title
              step = 3
            } else if let initialTrain {
              date = Time.parse(initialTrain.originServiceDate + "T12:00:00-05:00") ?? date
              pick(initialTrain)
            }
            if initialJourney == nil, let scenario = store.qaScenario { configurePreview(scenario) }
            if initialJourney == nil && store.trains.isEmpty { await store.refresh() }
          }
      }
    }.presentationDetents([.large]).presentationCornerRadius(28)
      .interactiveDismissDisabled()
      .task(id: candidateRequest) {
        let request = candidateRequest
        guard request.active else { return }
        let snapshots = store.trains
        let previousIndex = candidateIndex
        indexing = true
        let work = Task.detached(priority: .userInitiated) {
          TrainSearchIndex.candidates(trains: snapshots, serviceDate: request.date,
            previous: request.previous, reusing: previousIndex)
        }
        let index = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
        guard !Task.isCancelled else { return }
        candidateIndex = index
        matchingCandidates = index.search(appliedQuery)
        preparedRequest = request
        indexing = false
      }
      .task(id: query) {
        if !query.isEmpty {
          do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
        }
        guard !Task.isCancelled else { return }
        appliedQuery = query
        matchingCandidates = candidateIndex.search(query)
      }
  }
  private var searchStep: some View {
    let visibleTrains = candidates
    let chosenID = visibleTrains.first(where: { $0.id == chosenTrain?.id })?.id ?? visibleTrains.first?.id
    return LazyVStack(alignment: .leading, spacing: 18) {
      Text(connectionStation == nil ? L10n.text("选择列车") : L10n.text("添加同站换乘")).font(.system(size: 32, weight: .semibold))
      Text(L10n.text("按车次号或车站搜索，选择始发服务日期。")).font(.system(size: 13)).foregroundStyle(VIATheme.muted)
      HStack(spacing: 8) {
        Image(systemName: "magnifyingglass").foregroundStyle(VIATheme.muted)
        TextField(L10n.text("搜索车次或车站"), text: $query).submitLabel(.done)
          .autocorrectionDisabled().textInputAutocapitalization(.never).focused($fieldFocused)
        if !query.isEmpty {
          Button(L10n.text("清除搜索"), systemImage: "xmark.circle.fill") { query = "" }
            .labelStyle(.iconOnly).foregroundStyle(VIATheme.muted).frame(minWidth: 44, minHeight: 44)
        }
      }.font(.system(size: 14)).padding(13).background(
        VIATheme.line, in: RoundedRectangle(cornerRadius: 12))
      VIACard(padding: 15) {
        DatePicker(L10n.text("始发服务日期"), selection: $date, displayedComponents: .date).datePickerStyle(.compact)
          .font(.system(size: 14)).environment(\.timeZone, TimeZone(identifier: "America/Toronto")!)
      }
      Picker(L10n.text("班次"), selection: $notDepartedOnly) {
        Text(L10n.text("全部班次")).tag(false)
        Text(L10n.text("尚未发车")).tag(true)
      }.pickerStyle(.segmented)
      if let connectionStation {
        Notice(
          text: L10n.text("下一段上车站固定为 %@，仅支持同站换乘。", String(describing: legs.last?.alighting?.name ?? connectionStation)),
          symbol: "arrow.triangle.branch")
      }
      if let message = store.sourceMessage { Notice(text: message) }
      if indexing {
        ProgressView(L10n.text("正在查找列车…")).frame(maxWidth: .infinity)
      } else if visibleTrains.isEmpty {
        ContentUnavailableView(
          connectionStation == nil ? L10n.text("暂无可用班次") : L10n.text("暂无同站可接续班次"), systemImage: "tram",
          description: Text(L10n.text("可更换日期；缺少参考车次时无法生成时刻。")))
        Button(L10n.text("刷新列车数据")) { Task { await store.refresh() } }
      }
      ForEach(visibleTrains) { train in
        Button {
          chosenTrain = train
        } label: {
          VStack(alignment: .leading, spacing: 8) {
            TrainRow(train: train, selected: chosenID == train.id)
            if train.originServiceDate != serviceDate {
              Text(L10n.text("参考时刻 · 出发前请确认班次")).font(.caption).foregroundStyle(
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
      Text(L10n.text("选择上下车站")).font(.system(size: 32, weight: .semibold))
      Text(L10n.text("点击车站，从本班列车的停靠站中选择。")).font(.system(size: 13)).foregroundStyle(VIATheme.muted)
      if let selected {
        VIACard(padding: 17) {
          HStack {
            Text("VIA \(selected.trainNumber)").font(.system(size: 12, weight: .semibold))
            Spacer()
            Text(selected.originServiceDate).font(.system(size: 12)).foregroundStyle(VIATheme.muted)
          }
        }
        if selectedSource == .reference { Notice(text: L10n.text("这是参考时刻，出发前请确认列车是否开行。")) }

        VIACard {
          Button {
            if connectionStation == nil { picker = "boarding" }
          } label: {
            stationField(
              L10n.text("上车站"), call: selected.calls.first { $0.index == boarding }, event: \.departure)
          }.buttonStyle(.plain).disabled(connectionStation != nil).accessibilityIdentifier(
            "boarding-station")
          Divider()
          Button {
            picker = "alighting"
          } label: {
            stationField(
              L10n.text("下车站"), call: selected.calls.first { $0.index == alighting }, event: \.arrival)
          }.buttonStyle(.plain).accessibilityIdentifier("alighting-station")
        }
        VIASectionLabel(title: L10n.text("本段停靠"))
        VIACard {
          StationTimeline(
            calls: selected.calls, boardingIndex: boarding, alightingIndex: alighting,
            plannedOnly: true)
        }

      }
    }
  }
  private func stationField(
    _ title: String, call: StationCall?, event: KeyPath<StationCall, EventTime?>
  ) -> some View {
    HStack(spacing: 12) {
      Image(systemName: title == L10n.text("上车站") ? "location" : "mappin.and.ellipse").foregroundStyle(
        VIATheme.accent)
      Text(title).font(.system(size: 14))
      Spacer()
      Text(call?.name ?? L10n.text("请选择")).font(.system(size: 14, weight: .medium))
      Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(VIATheme.accent)
    }.frame(minHeight: 38).contentShape(Rectangle())
  }

  private var planningStep: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text(planningPart == 0 ? L10n.text("确认发车时间") : L10n.text("前往车站耗时")).font(.system(size: 32, weight: .semibold))
      Text(planningPart == 0 ? L10n.text("我们会根据这个时间提醒你出门。") : L10n.text("包含前往车站及自行预留的时间。"))
        .font(.system(size: 13)).foregroundStyle(VIATheme.muted)
      if planningPart == 0 {
        VIACard {
          HStack {
            Text(L10n.text("官方计划")).foregroundStyle(VIATheme.muted)
            Spacer()
            Text(
              Time.format(selected?.calls.first { $0.index == boarding }?.departure?.scheduledDate, zone: boardingZone))
          }.font(.system(size: 14))
        }
        DatePicker(L10n.text("规划发车"), selection: $planning, displayedComponents: [.date, .hourAndMinute])
          .datePickerStyle(.wheel).labelsHidden().frame(maxWidth: .infinity)
          .environment(
            \.timeZone,
            TimeZone(
              identifier: selected?.calls.first { $0.index == boarding }?.timeZone
                ?? "America/Toronto")!)
        Notice(text: L10n.text("规划时间由你设置。列车延误不会自动推迟计划出门。"))
      } else {
        VIACard {
          HStack {
            VStack(alignment: .leading, spacing: 6) {
              Text(L10n.text("前往上车站")).font(.system(size: 12)).foregroundStyle(VIATheme.muted)
              Text(selected?.calls.first { $0.index == boarding }?.name ?? "").font(
                .system(size: 16, weight: .semibold))
            }
            Spacer()
            Image(systemName: "figure.walk").font(.system(size: 23))
          }
        }
        HStack {
          minuteButton("minus", label: L10n.text("减少15分钟")) { minutes = max(0, minutes - 15) }.disabled(
            minutes == 0)
          Spacer()
          VStack(spacing: 10) {
            Text("\(minutes)").font(.system(size: 88, weight: .light)).tracking(-6)
              .monospacedDigit()
            Text(L10n.text("分钟")).font(.system(size: 13)).foregroundStyle(VIATheme.muted)
          }.accessibilityElement(children: .ignore).accessibilityLabel(L10n.text("前往车站 %@ 分钟", String(describing: minutes)))
          Spacer()
          minuteButton("plus", label: L10n.text("增加15分钟")) { minutes = min(1440, minutes + 15) }.disabled(
            minutes == 1440)
        }.padding(.vertical, 28)
        Text(L10n.text("每次调整 15 分钟 · 最少 0 分钟")).font(.system(size: 10)).foregroundStyle(VIATheme.muted).frame(
          maxWidth: .infinity)
        VIACard(tinted: true, padding: 20, spacing: 14) {
          Text(L10n.text("计划出门时间")).font(.system(size: 12)).foregroundStyle(VIATheme.accent)
          Text(Time.format(planning.addingTimeInterval(-Double(minutes * 60)), zone: boardingZone))
            .font(.system(size: 46)).tracking(-2).monospacedDigit()
          Text(L10n.text("规划发车 %@ − 前往耗时 %@ 分钟", String(describing: Time.format(planning, zone: boardingZone)), String(describing: minutes))).font(.system(size: 12))
            .foregroundStyle(VIATheme.muted)
        }
      }
    }
  }
  private func minuteButton(_ symbol: String, label: String, action: @escaping () -> Void)
    -> some View
  {
    Button(action: action) {
      Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(VIATheme.accent)
        .frame(width: 55, height: 55).background(VIATheme.tintSurface, in: Circle())
    }.buttonStyle(.plain).accessibilityLabel(label)
  }
  private var footer: some View {
    VStack(spacing: 10) {
      if step == 0 {
        Button(L10n.text("下一步")) { if let train = resolvedTrain { pick(train) } }
          .buttonStyle(PrimaryButtonStyle()).disabled(indexing || candidates.isEmpty || appliedQuery != query)
      } else if step == 1 {
        Button(L10n.text("下一步")) {
          if let departure = selected?.calls.first(where: { $0.index == boarding })?.departure?
            .scheduledDate
          {
            if editingIndex == nil { planning = departure }
            planningPart = 0
            step = 2
          }
        }.buttonStyle(PrimaryButtonStyle()).disabled(boarding == nil || alighting == nil)
          .accessibilityIdentifier("next-stations")
      } else if step == 2 {
        Button(planningPart == 0 ? L10n.text("下一步") : L10n.text("预览行程")) {
          if planningPart == 0 && (legs.isEmpty || editingIndex == 0) {
            planningPart = 1
          } else {
            let official = selected?.calls.first { $0.index == boarding }?.departure?.scheduledDate
            if selectedSource == .official, let official,
              abs(official.timeIntervalSince(planning)) >= 60
            {
              confirmPlanning = true
            } else {
              commitLeg()
            }
          }
        }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier(
          planningPart == 0 ? "next-planning" : "confirm-leg")
      } else {
        Button(initialJourney == nil ? (startOnSave && !savesAsUpcoming ? L10n.text("开启实时活动") : L10n.text("保存行程")) : L10n.text("保存修改")) { save() }
          .buttonStyle(PrimaryButtonStyle()).disabled(legs.isEmpty).accessibilityIdentifier(
            "save-journey")
        Text(L10n.text("行程同时保存在本机")).font(.system(size: 10)).foregroundStyle(VIATheme.muted)
      }
    }.padding(.horizontal, 24).padding(.vertical, 12)
      .frame(maxWidth: 700).frame(maxWidth: .infinity).background(VIATheme.background)
      .overlay(alignment: .top) { VIADivider() }
  }
  private var reviewStep: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text(initialJourney != nil ? L10n.text("调整行程安排") : legs.count > 1 ? L10n.text("确认换乘行程") : L10n.text("确认行程")).font(.system(size: 32, weight: .semibold))
      Text(initialJourney != nil ? L10n.text("修改乘车区间、出门安排或行程名称，保存后生效。") : L10n.text("核对乘车区间和计划出门时间。")).font(.system(size: 13)).foregroundStyle(VIATheme.muted)
      ForEach(Array(legs.enumerated()), id: \.element.id) { i, leg in
        VIACard(padding: 17, spacing: 16) {
          HStack {
            Label("VIA \(leg.trainNumber)", systemImage: "tram.fill").font(
              .system(size: 12, weight: .semibold))
            Spacer()
            Button(L10n.text("修改")) {
              editLeg(i, at: 1)
            }.font(.subheadline).frame(minWidth: 44, minHeight: 44).foregroundStyle(VIATheme.accent)
          }
          Text("\(leg.boarding?.name ?? "")  →  \(leg.alighting?.name ?? "")")
            .font(.system(size: 22, weight: .semibold)).tracking(-0.7)
          HStack(spacing: 14) {
            VStack(spacing: 0) {
              Circle().stroke(VIATheme.accent, lineWidth: 2).frame(width: 8, height: 8)
              Rectangle().fill(VIATheme.yellow).frame(width: 3, height: 43)
              Circle().stroke(VIATheme.accent, lineWidth: 2).frame(width: 8, height: 8)
            }
            VStack(spacing: 20) {
              HStack {
                Text(leg.boarding?.name ?? "")
                Spacer()
                Text(
                  Time.format(
                    leg.boarding?.departure?.scheduledDate,
                    zone: leg.boarding?.timeZone ?? "America/Toronto")
                ).font(.system(size: 20)).monospacedDigit()
              }
              HStack {
                Text(leg.alighting?.name ?? "")
                Spacer()
                Text(
                  Time.format(
                    leg.alighting?.arrival?.scheduledDate,
                    zone: leg.alighting?.timeZone ?? "America/Toronto")
                ).font(.system(size: 20)).monospacedDigit()
              }
            }.font(.system(size: 14))
          }
          if leg.source == .reference { StatusPill(title: L10n.text("参考时刻"), warning: true) }
          if i > 0, let previous = legs[i - 1].alighting?.arrival?.effectiveDate,
            let departure = leg.boarding?.departure?.scheduledDate
          {
            Text(L10n.text("同站接续间隔 %@ 分钟", String(describing: Int(departure.timeIntervalSince(previous)/60)))).font(
              .system(size: 12)
            ).foregroundStyle(VIATheme.accent)
          }
          if i == legs.count - 1 && legs.count > 1 {
            Button(L10n.text("移除末段"), role: .destructive) { legs.removeLast() }.font(.system(size: 12))
          }
        }
      }
      if let first = legs.first {
        VIACard(padding: 16, spacing: 0) {
          HStack {
            Label(L10n.text("计划出门"), systemImage: "house").foregroundStyle(VIATheme.accent)
            Spacer()
            Text(
              Time.format(
                Date(timeIntervalSince1970: first.planningDeparture - Double(minutes * 60)),
                zone: first.boarding?.timeZone ?? "America/Toronto"))
          }.frame(minHeight: 40)
          VIADivider()
          HStack {
            Label(L10n.text("前往车站"), systemImage: "figure.walk")
            Spacer()
            Text(L10n.text("%@ 分钟", String(describing: minutes)))
          }.frame(minHeight: 55)
          Button(L10n.text("调整出门安排"), systemImage: "clock") { editLeg(0, at: 2) }
            .frame(minHeight: 44).foregroundStyle(VIATheme.accent)
          if initialJourney == nil {
            VIADivider()
            Toggle(L10n.text("实时活动"), isOn: $startOnSave).tint(VIATheme.yellow).frame(minHeight: 55)
          }
        }.font(.system(size: 14))
      }
      Button(L10n.text("添加同站换乘"), systemImage: "plus") {
        editingIndex = nil
        chosenTrain = nil
        query = ""
        if let last = legs.last?.alighting?.arrival?.scheduledDate { date = last }
        step = 0
      }.buttonStyle(SecondaryButtonStyle()).disabled(legs.count >= 16)
      Text(L10n.text("行程名称")).font(.subheadline.weight(.medium))
      TextField(L10n.text("行程名称（可选）"), text: $name).font(.system(size: 14))
        .submitLabel(.done).focused($fieldFocused).padding(16)
        .background(VIATheme.surface, in: RoundedRectangle(cornerRadius: 14))
      Notice(
        text: savesAsUpcoming
          ? L10n.text("行程会在出门前 5 小时开始倒计时；已打开「实时活动」时，届时自动显示在锁定屏幕。")
          : L10n.text("实时活动最长持续 8 小时。到期后可打开 App 续开。"))
    }
  }
  private func editLeg(_ index: Int, at destination: Int) {
    guard legs.indices.contains(index) else { return }
    let leg = legs[index]
    editingIndex = index
    selected = leg.snapshot
    selectedSource = leg.source
    referenceID = leg.referenceInstanceID
    boarding = leg.boardingIndex
    alighting = leg.alightingIndex
    planning = Date(timeIntervalSince1970: leg.planningDeparture)
    planningPart = 0
    step = destination
  }
  private func pick(_ train: TrainSnapshot, repeatedTime: ReferenceSchedule.RepeatedTime? = nil) {
    do {
      selectedSource = train.originServiceDate == serviceDate ? .official : .reference
      referenceID = selectedSource == .reference ? train.id : nil
      let snapshot =
        selectedSource == .reference
        ? try ReferenceSchedule.migrate(train, to: serviceDate, repeatedTime: repeatedTime) : train
      let b = snapshot.calls.first { call in
        (connectionStation == nil || call.code == connectionStation) && call.departure != nil
          && call.index < (snapshot.calls.last?.index ?? 0)
          && (editingIndex != nil || (legs.last?.alighting?.arrival?.scheduledDate.map { previous in
            call.departure?.scheduledDate.map { $0 >= previous } ?? false
          } ?? true))
      }
      guard let b, let a = snapshot.calls.last(where: { $0.arrival != nil && $0.index > b.index })
      else { throw ReferenceError.missingStations }
      if let previous = legs.last?.alighting?.arrival?.scheduledDate, editingIndex == nil,
        let dep = b.departure?.scheduledDate, dep < previous
      {
        error = L10n.text("此班次计划发车早于上一段计划到达，请更换日期或车次。")
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
        error = L10n.text("该日期包含不存在的夏令时时刻，请更换日期或等待正式时刻。")
      }
    } catch { self.error = error.localizedDescription }
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
    if step == 2 && planningPart == 1 {
      planningPart = 0
      return
    }
    if step == 3, let i = legs.indices.last {
      let leg = legs[i]
      editingIndex = i
      selected = leg.snapshot
      selectedSource = leg.source
      referenceID = leg.referenceInstanceID
      boarding = leg.boardingIndex
      alighting = leg.alightingIndex
      planning = Date(timeIntervalSince1970: leg.planningDeparture)
      planningPart = i == 0 ? 1 : 0
      step = 2
    } else if step == 1 && editingIndex != nil {
      editingIndex = nil
      step = 3
    } else {
      step = max(0, step - 1)
    }
  }
  private func requestCancel() {
    fieldFocused = false
    if selected != nil || !legs.isEmpty { confirmDiscard = true } else { dismiss() }
  }
  private func save() {
    guard !legs.isEmpty else { return }
    for i in legs.indices.dropFirst() {
      if legs[i - 1].alightingCode != legs[i].boardingCode {
        error = L10n.text("第 %@ 段与上一段不是同站接续，请修改车段。", String(describing: i+1))
        return
      }
    }
    var j = initialJourney ?? Journey(legs: legs)
    j.legs = legs
    j.travelToStationMinutes = minutes
    j.title = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
    j.currentLegIndex = min(j.currentLegIndex, legs.count - 1)
    guard store.save(j) else {
      error = store.storageError ?? L10n.text("行程未能保存，请重试。")
      return
    }
    store.selectedJourneyID = j.id
    if startOnSave && initialJourney == nil && store.qaScenario == nil {
      Task { await store.startActivity(j) }
    }
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
      planningPart = scenario == "travel" ? 1 : 0
      if scenario == "manual-warning" { confirmPlanning = true }
      if scenario == "boarding-picker" { picker = "boarding" }
      if scenario == "alighting-picker" { picker = "alighting" }
    }
  }
  private func stationPicker(_ kind: String) -> some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 0) {
          ForEach(selected?.calls ?? []) { call in
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
              }.padding(.vertical, 18).padding(.horizontal, 16)
            }.disabled(!allowed).accessibilityIdentifier("station-\(call.index)")
            VIADivider()
          }
        }.background(VIATheme.surface, in: RoundedRectangle(cornerRadius: 20)).padding(24)
      }.viaBackground().toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top) {
          VIANavigationBar(title: kind == "boarding" ? L10n.text("选择上车站") : L10n.text("选择下车站")) {
            Button(L10n.text("完成")) { picker = nil }
          }
        }
    }.presentationDetents([.medium, .large])
  }
}
