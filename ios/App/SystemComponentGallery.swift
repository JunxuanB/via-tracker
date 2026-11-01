#if DEBUG
  import SwiftUI
  import TrackerCore
  import WidgetKit

  /// Reuses the extension's content. The surrounding frames approximate system hosts only.
  struct SystemComponentGallery: View {
    var scenario: String
    var initialJourney: Journey
    private var journey: Journey {
      var j = initialJourney
      let offset =
        Date().timeIntervalSince1970
        - (Time.parse("2026-11-06T17:24:00-05:00")!.timeIntervalSince1970)
      for i in j.legs.indices {
        for k in j.legs[i].snapshot.calls.indices {
          for arrival in [true, false] {
            let event =
              arrival ? j.legs[i].snapshot.calls[k].arrival : j.legs[i].snapshot.calls[k].departure
            if let event, let scheduled = event.scheduledDate {
              let moved = EventTime(
                scheduled: Time.iso(scheduled.addingTimeInterval(offset)),
                estimated: event.estimatedDate.map { Time.iso($0.addingTimeInterval(offset)) })
              if arrival {
                j.legs[i].snapshot.calls[k].arrival = moved
              } else {
                j.legs[i].snapshot.calls[k].departure = moved
              }
            }
          }
        }
        j.legs[i].snapshot.sourceFetchedAt = Time.iso(Date())
        j.legs[i].planningDeparture += offset
      }
      return j
    }
    var body: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          Notice(text: "系统组件布局预览 · 系统锁屏与推送送达待真机验收。")
          if scenario == "widgets" {
            Text("小号组件").font(.headline)
            JourneyWidgetView(
              entry: JourneyEntry(date: Date(), journey: journey), familyOverride: .systemSmall
            )
            .padding(16).frame(width: 170, height: 170)
            .background(.background, in: RoundedRectangle(cornerRadius: 24))
            Text("中号组件").font(.headline)
            JourneyWidgetView(
              entry: JourneyEntry(date: Date(), journey: journey), familyOverride: .systemMedium
            )
            .padding(16).frame(height: 170).background(
              .background, in: RoundedRectangle(cornerRadius: 24))
          } else if scenario == "islands" {
            Notice(text: "以下复用灵动岛实际内容，外框仅为尺寸参考；长按后的系统留白仍需真机查看。")
            ForEach(Phase.allCases, id: \.self) { phase in
              Text(phase.title).font(.headline)
              islandPreview(state(phase))
            }
            Text("窄布局 · 长站名 · 超过一天").font(.headline)
            islandPreview(longRoute, width: 300, stale: true, testMode: true)
            Text("到达晚于下一段发车").font(.headline)
            islandPreview(tightConnection, width: 300, testMode: true)
            Text("紧凑与最小内容").font(.headline)
            HStack(spacing: 16) {
              HStack(spacing: 12) {
                Image(systemName: longRoute.phase.symbol).foregroundStyle(VIATheme.yellow)
                Color.clear.frame(width: 60, height: 20).accessibilityHidden(true)
                IslandCompactTime(state: longRoute)
              }.padding(12).background(.black, in: Capsule())
              Image(systemName: longRoute.phase.symbol).foregroundStyle(VIATheme.yellow)
                .padding(12).background(.black, in: Circle())
            }.foregroundStyle(.white).environment(\.colorScheme, .dark)
          } else {
            ForEach(Phase.allCases, id: \.self) { phase in
              let state = state(phase)
              Text(phase.title).font(.headline)
              ActivitySummary(state: state, stale: false).padding(16).background(
                .background, in: RoundedRectangle(cornerRadius: 24))
            }
            if let state = Projection.state(journey) {
              Text("数据较旧").font(.headline)
              ActivitySummary(state: state, stale: true).padding(16).background(
                .background, in: RoundedRectangle(cornerRadius: 24))
            }
          }
        }.padding(24)
      }.viaBackground().navigationTitle("系统组件")
    }
    private func islandPreview(
      _ state: TrackerCore.ActivityState, width: CGFloat = 350, stale: Bool = false,
      testMode: Bool = false
    ) -> some View {
      VStack(spacing: 8) {
        HStack(alignment: .center, spacing: 6) {
          IslandTrainLabel(state: state)
          Spacer(minLength: 0)
          Color.clear.frame(width: 84, height: 30).accessibilityHidden(true)
          Spacer(minLength: 0)
          IslandStatusLabel(state: state, stale: stale, testMode: testMode)
        }
        IslandExpandedContent(state: state, stale: stale)
        Spacer(minLength: 0)
      }.padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: width).frame(height: 160, alignment: .top)
        .foregroundStyle(.white).environment(\.colorScheme, .dark)
        .background(.black, in: RoundedRectangle(cornerRadius: 36))
    }
    private var longRoute: TrackerCore.ActivityState {
      var value = state(.riding)
      value.origin = "Sainte-Foy (Québec)"
      value.destination = "Saint-Lambert (Montréal)"
      value.targetEpoch = Date().addingTimeInterval(27 * 3600 + 15 * 60).timeIntervalSince1970
      value.progress = 0.35
      return value
    }
    private var tightConnection: TrackerCore.ActivityState {
      var value = state(.riding)
      value.nextTrainNumber = "38"
      value.nextDepartureEpoch = value.targetEpoch - 12 * 60
      value.connectionMinutes = -12
      return value
    }
    private func state(_ phase: Phase) -> TrackerCore.ActivityState {
      var j = journey
      j.manualPhase = phase
      j.completed = phase == .completed
      var state = Projection.state(j)!
      state.phase = phase
      state.nextTrainNumber = nil
      state.nextDepartureEpoch = nil
      state.connectionMinutes = nil
      state.progress = phase == .completed ? 1 : phase == .riding ? 0.64 : 0
      let now = Date().timeIntervalSince1970
      switch phase {
      case .beforeDeparture: state.targetEpoch = now + 35 * 60
      case .onTheWay: state.targetEpoch = now + 18 * 60
      case .waiting: state.targetEpoch = now + 13 * 60
      case .riding: state.targetEpoch = now + 46 * 60
      case .transferring:
        state.targetEpoch = now + 33 * 60
        state.trainNumber = "38"
        state.origin = "Ottawa"
        state.destination = "Montréal"
        state.currentLegIndex = 1
        state.legCount = 2
      case .completed: state.targetEpoch = now - 60
      }
      state.waitingForUpdate = false
      return state
    }
  }
#endif
