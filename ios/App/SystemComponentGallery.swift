#if DEBUG
  import SwiftUI
  import TrackerCore
  import WidgetKit

  /// Uses the extension's actual SwiftUI views. This checks layout, not system delivery or lock-screen placement.
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
    private func state(_ phase: Phase) -> TrackerCore.ActivityState {
      var j = journey
      j.manualPhase = phase
      j.completed = phase == .completed
      var state = Projection.state(j)!
      let now = Date().timeIntervalSince1970
      switch phase {
      case .beforeDeparture: state.targetEpoch = now + 35 * 60
      case .onTheWay: state.targetEpoch = now + 18 * 60
      case .waiting: state.targetEpoch = now + 13 * 60
      case .transferring:
        state.targetEpoch = now + 33 * 60
        state.trainNumber = "38"
        state.origin = "Ottawa"
        state.destination = "Montréal"
        state.currentLegIndex = 1
        state.legCount = 2
      default: break
      }
      state.waitingForUpdate = false
      return state
    }
  }
#endif
