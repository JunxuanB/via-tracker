#if DEBUG
  import Foundation
  import TrackerCore
  @MainActor enum PreviewScenarios {
    static var base: Journey { try! JSONDecoder().decode(Journey.self, from: Data(raw.utf8)) }
    static func configure(_ store: AppStore, scenario: String) {
      var j = base
      store.activities.configurePreview(scenario)
      store.appearance = scenario.contains("dark") ? "dark" : "light"
      if scenario == "empty" || scenario == "ui-test" {
        if scenario == "empty" { store.journeys = [] }
        if scenario == "ui-test" {
          store.trains = [j.legs[0].snapshot]
          store.selectedJourneyID = store.journeys.first?.id
        }
        return
      }
      let phase: Phase =
        switch scenario {
        case "before", "upcoming": .beforeDeparture
        case "onway": .onTheWay
        case "waiting": .waiting
        case "interchange": .transferring
        case "complete": .completed
        default: .riding
        }
      j.manualPhase = phase
      j.completed = phase == .completed
      if scenario == "waiting" {
        j.legs[0].snapshot.calls[0].departure?.estimated = "2026-11-06T14:08:00-05:00"
      }
      if scenario == "stale-position" {
        j.legs[0].snapshot.position = TrainPosition(
          latitude: 45.1, longitude: -75.7, reportedAt: "2026-11-06T17:00:00-05:00")
      }
      if scenario == "midboard" {
        j.legs[0].boardingIndex = 1
        j.legs[0].boardingCode = "KGON"
      }
      if scenario == "crossday" {
        j.legs[0].snapshot.calls[0].departure = EventTime(scheduled: "2026-11-06T23:10:00-05:00")
        j.legs[0].snapshot.calls[1].arrival = EventTime(scheduled: "2026-11-07T00:30:00-05:00")
        j.legs[0].snapshot.calls[1].departure = EventTime(scheduled: "2026-11-07T00:32:00-05:00")
        j.legs[0].snapshot.calls[2].arrival = EventTime(scheduled: "2026-11-07T02:20:00-05:00")
        j.legs[0].planningDeparture = j.legs[0].snapshot.calls[0].departure!.scheduledDate!.timeIntervalSince1970
      }
      if scenario == "timezone" {
        j.legs[0].boardingCode = "KAMN"
        j.legs[0].alightingCode = "JASP"
        j.legs[0].snapshot.calls[0].code = "KAMN"
        j.legs[0].snapshot.calls[0].timeZone = "America/Vancouver"
        j.legs[0].snapshot.calls[0].name = "Kamloops North"
        j.legs[0].snapshot.calls[0].departure = EventTime(scheduled: "2026-11-07T00:17:00-08:00")
        j.legs[0].snapshot.calls[1].code = "BLUE"
        j.legs[0].snapshot.calls[1].name = "Blue River"
        j.legs[0].snapshot.calls[1].timeZone = "America/Vancouver"
        j.legs[0].snapshot.calls[1].arrival = EventTime(scheduled: "2026-11-07T05:11:00-08:00")
        j.legs[0].snapshot.calls[1].departure = EventTime(scheduled: "2026-11-07T05:13:00-08:00")
        j.legs[0].snapshot.calls[2].code = "JASP"
        j.legs[0].snapshot.calls[2].timeZone = "America/Edmonton"
        j.legs[0].snapshot.calls[2].name = "Jasper"
        j.legs[0].snapshot.calls[2].arrival = EventTime(scheduled: "2026-11-07T11:00:00-07:00")
        j.legs[0].snapshot.from = "KAMLOOPS NORTH"
        j.legs[0].snapshot.to = "JASPER"
        j.legs[0].planningDeparture = j.legs[0].snapshot.calls[0].departure!.scheduledDate!.timeIntervalSince1970
      }
      if [
        "connection", "interchange", "second-leg", "home", "ipad-detail", "ipad-dark",
        "ipad-narrow", "transfer-review", "negative-connection", "zero-connection", "widgets",
      ].contains(scenario) {
        var next = j.legs[0]
        next.id = "leg-2"
        next.trainNumber = "38"
        next.boardingCode = "OTTW"
        next.boardingIndex = 0
        next.alightingCode = "MTRL"
        next.alightingIndex = 1
        next.snapshot = TrainSnapshot(
          id: "38:2026-11-06", trainNumber: "38", originServiceDate: "2026-11-06", rawKey: "38",
          from: "OTTAWA", to: "MONTRÉAL",
          calls: [
            StationCall(
              index: 0, code: "OTTW", name: "Ottawa", timeZone: "America/Toronto",
              departure: EventTime(scheduled: "2026-11-06T19:15:00-05:00")),
            StationCall(
              index: 1, code: "MTRL", name: "Montréal", timeZone: "America/Toronto",
              arrival: EventTime(scheduled: "2026-11-06T21:12:00-05:00")),
          ], sourceFetchedAt: j.legs[0].snapshot.sourceFetchedAt, version: 1)
        next.planningDeparture = next.boarding!.departure!.scheduledDate!.timeIntervalSince1970
        j.legs.append(next)
        if scenario == "negative-connection" || scenario == "zero-connection" {
          j.legs[0].snapshot.calls[2].arrival?.estimated =
            scenario == "negative-connection"
            ? "2026-11-06T19:27:00-05:00" : "2026-11-06T19:15:00-05:00"
        }
        if scenario == "interchange" || scenario == "second-leg" { j.currentLegIndex = 1 }
      }
      if ["reference", "sync", "notification"].contains(scenario) {
        if scenario == "reference" {
          j.legs[0].source = .reference
          j.legs[0].snapshot = try! ReferenceSchedule.migrate(
            j.legs[0].snapshot, to: j.legs[0].originServiceDate)
        } else {
          j.pendingScheduleChange = true
          j.scheduleChangePrompted = true
          j.legs[0].planningDeparture -= 600
        }
      }
      if scenario == "offline" {
        store.isOffline = true
        store.errorMessage = nil
      }
      if scenario == "server-error" { store.errorMessage = L10n.text("暂时无法更新 · 保留最近有效数据") }
      if scenario == "recovered" { store.recoveredAt = Date() }
      if scenario == "pending-update" {
        j.legs[0].snapshot.calls[2].arrival?.estimated = "2026-11-06T17:20:00-05:00"
      }
      store.save(j)
      store.primaryID = j.id
      store.trains = j.legs.map(\.snapshot)
      if scenario == "add-transfer" {
        store.trains.append(
          TrainSnapshot(
            id: "38:2026-11-06", trainNumber: "38", originServiceDate: "2026-11-06", rawKey: "38",
            from: "OTTAWA", to: "MONTRÉAL",
            calls: [
              StationCall(
                index: 0, code: "OTTW", name: "Ottawa", timeZone: "America/Toronto",
                departure: EventTime(scheduled: "2026-11-06T19:15:00-05:00")),
              StationCall(
                index: 1, code: "MTRL", name: "Montréal", timeZone: "America/Toronto",
                arrival: EventTime(scheduled: "2026-11-06T21:12:00-05:00")),
            ], sourceFetchedAt: j.legs[0].snapshot.sourceFetchedAt, version: 1))
      }
      if !["home", "upcoming", "settings"].contains(scenario) { store.selectedJourneyID = j.id }
    }
    static let raw = #"""
      {
        "id": "fixture-journey",
        "title": "",
        "createdAt": 1793984400.0,
        "legs": [
          {
            "id": "leg-1",
            "trainNumber": "44",
            "originServiceDate": "2026-11-06",
            "boardingCode": "TRTO",
            "boardingIndex": 0,
            "alightingCode": "OTTW",
            "alightingIndex": 2,
            "planningDeparture": 1793991600.0,
            "source": "official",
            "snapshot": {
              "id": "44:2026-11-06",
              "trainNumber": "44",
              "originServiceDate": "2026-11-06",
              "rawKey": "44",
              "from": "TORONTO",
              "to": "OTTAWA",
              "departed": true,
              "arrived": false,
              "calls": [
                {
                  "index": 0,
                  "code": "TRTO",
                  "name": "Toronto",
                  "timeZone": "America/Toronto",
                  "departure": {
                    "scheduled": "2026-11-06T14:00:00-05:00"
                  }
                },
                {
                  "index": 1,
                  "code": "KGON",
                  "name": "Kingston",
                  "timeZone": "America/Toronto",
                  "departure": {
                    "scheduled": "2026-11-06T16:22:00-05:00"
                  },
                  "arrival": {
                    "scheduled": "2026-11-06T16:20:00-05:00"
                  }
                },
                {
                  "index": 2,
                  "code": "OTTW",
                  "name": "Ottawa",
                  "timeZone": "America/Toronto",
                  "arrival": {
                    "scheduled": "2026-11-06T18:30:00-05:00",
                    "estimated": "2026-11-06T18:42:00-05:00"
                  }
                }
              ],
              "sourceFetchedAt": "2026-11-06T22:24:00Z",
              "version": 1,
              "alerts": []
            }
          }
        ],
        "travelToStationMinutes": 30,
        "currentLegIndex": 0,
        "completed": false,
        "trackingEnded": false,
        "syncChoice": "ask",
        "pendingScheduleChange": false,
        "scheduleChangePrompted": false,
        "manualPhase": "riding"
      }
      """#
  }
#endif
