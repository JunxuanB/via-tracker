import Foundation
import Testing

@testable import TrackerCore

struct ProjectionCase: Decodable {
  var name: String
  var journey: Journey
  var now: Double
  var expectedPhase: Phase
  var expectedTarget: Double
  var expectedWaiting: Bool
  var expectedConnectionMinutes: Int?
}
let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
  .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  .deletingLastPathComponent().appendingPathComponent("contracts/fixtures")
func cases() throws -> [ProjectionCase] {
  try JSONDecoder().decode(
    [ProjectionCase].self,
    from: Data(contentsOf: fixtures.appendingPathComponent("projections.json")))
}

@Test func sharedProjectionFixtures() throws {
  for test in try cases() {
    let state = try #require(
      Projection.state(test.journey, now: Date(timeIntervalSince1970: test.now)))
    #expect(state.phase == test.expectedPhase, Comment(rawValue: test.name))
    #expect(state.targetEpoch == test.expectedTarget)
    #expect(state.waitingForUpdate == test.expectedWaiting)
    #expect(state.progress >= 0 && state.progress <= 1)
    if let expected = test.expectedConnectionMinutes {
      #expect(state.connectionMinutes == expected)
    }
  }
}
@Test func planningDoesNotFollowDelay() throws {
  var j = try cases()[0].journey
  let leave = j.plannedLeaveAt
  j.legs[0].snapshot.calls[0].departure?.estimated = "2026-11-06T15:00:00-05:00"
  #expect(j.plannedLeaveAt == leave)
  j.travelToStationMinutes = 0
  #expect(j.plannedLeaveAt.timeIntervalSince1970 == j.legs[0].planningDeparture)
}
@Test func referenceKeepsLocalTimeAndClearsRunningData() throws {
  let s = try cases()[0].journey.legs[0].snapshot
  let moved = try ReferenceSchedule.migrate(s, to: "2026-11-07")
  #expect(moved.position == nil && !moved.departed && !moved.arrived)
  #expect(moved.calls.allSatisfy { $0.arrival?.estimated == nil && $0.departure?.estimated == nil })
  #expect(Time.format(moved.calls[0].departure?.scheduledDate) == "14:00")
  var beforeDST = s
  beforeDST.originServiceDate = "2026-10-31"
  beforeDST.calls[0].departure = EventTime(scheduled: "2026-10-31T14:00:00-04:00")
  let afterDST = try ReferenceSchedule.migrate(beforeDST, to: "2026-11-01")
  let elapsed = try #require(afterDST.calls[0].departure?.scheduledDate).timeIntervalSince(
    try #require(beforeDST.calls[0].departure?.scheduledDate))
  #expect(abs(elapsed - 90000.0) < 0.01)
}
@Test func ambiguousAndNonexistentDSTTimesRequireConfirmation() throws {
  var s = try cases()[0].journey.legs[0].snapshot
  s.originServiceDate = "2026-10-31"
  s.calls[0].departure = EventTime(scheduled: "2026-10-31T01:30:00-04:00")
  #expect(throws: ReferenceError.self) { try ReferenceSchedule.migrate(s, to: "2026-11-01") }
  let first = try ReferenceSchedule.migrate(s, to: "2026-11-01", repeatedTime: .first)
  let last = try ReferenceSchedule.migrate(s, to: "2026-11-01", repeatedTime: .last)
  #expect(
    last.calls[0].departure!.scheduledDate!.timeIntervalSince(
      first.calls[0].departure!.scheduledDate!) == 3600)
  s.originServiceDate = "2026-03-07"
  s.calls[0].departure = EventTime(scheduled: "2026-03-07T02:30:00-05:00")
  #expect(throws: ReferenceError.self) { try ReferenceSchedule.migrate(s, to: "2026-03-08") }
}
@Test func sameNumberDifferentDateAndManualLegAdvance() throws {
  var j = try cases()[3].journey
  var other = j.legs[0].snapshot
  other.id = "44:2026-11-07"
  other.originServiceDate = "2026-11-07"
  other.version += 10
  #expect(Projection.reconcile(j, snapshots: [other]) == j)
  j.legs.append(j.legs[0])
  j.manualPhase = .riding
  j.advanceLeg()
  #expect(j.currentLegIndex == 1 && j.manualPhase == nil)
  let state = try #require(Projection.state(j, now: Date(timeIntervalSince1970: 1793991300)))
  #expect(state.phase == .transferring)
  var missingEstimate = j
  missingEstimate.manualPhase = .riding
  missingEstimate.legs[1].snapshot.calls[2].arrival?.estimated = nil
  #expect(Projection.state(missingEstimate)?.targetIsEstimate == false)
}
@Test func formalMatchingPromptsOnceAndStaysPerJourney() throws {
  var j = try cases()[0].journey
  j.legs[0].source = .reference
  j.legs[0].planningDeparture -= 600
  let updated = Projection.reconcile(j, snapshots: [j.legs[0].snapshot])
  #expect(updated.pendingScheduleChange && updated.scheduleChangePrompted)
  #expect(updated.legs[0].planningDeparture == j.legs[0].planningDeparture)
  var accepted = updated
  accepted.chooseSync(true)
  #expect(
    !accepted.pendingScheduleChange
      && accepted.legs[0].planningDeparture
        == accepted.legs[0].boarding?.departure?.scheduledDate?.timeIntervalSince1970
  )
  #expect(j.syncChoice == .ask)
}
@Test func payloadAndOldSnapshot() throws {
  let j = try cases()[3].journey
  let state = try #require(Projection.state(j))
  #expect(try JSONEncoder().encode(state).count < 3500)
  var old = j.legs[0].snapshot
  old.version = 0
  old.calls[2].arrival?.estimated = "2026-11-06T19:00:00-05:00"
  #expect(Projection.reconcile(j, snapshots: [old]) == j)
}

// Added for the automatic-arrival and multilingual-search changes; not executed in this review.
@Test func arrivalIsAutomaticAndLateETAStillUpdates() throws {
  let j = try cases()[3].journey
  let now = Date(timeIntervalSince1970: 1794008580)
  #expect(Projection.state(j, now: now)?.phase == .completed)
  #expect(!j.completed)
  var delayed = j.legs[0].snapshot
  delayed.version += 1
  delayed.calls[2].arrival?.estimated = "2026-11-06T19:00:00-05:00"
  let refreshed = Projection.reconcile(j, snapshots: [delayed])
  #expect(Projection.state(refreshed, now: now)?.phase == .riding)
}
@Test func searchIgnoresAccentsAndMatchesStationCodes() throws {
  var train = try cases()[3].journey.legs[0].snapshot
  train.calls[2].name = "Montréal"
  train.calls[2].code = "MTRL"
  let index = TrainSearchIndex(trains: [train])
  #expect(index.search("Montreal").map(\.id) == [train.id])
  #expect(index.search("  MONTRÉAL  ").map(\.id) == [train.id])
  #expect(index.search("mtrl").map(\.id) == [train.id])
}

@Test func reportedArrivalAtSelectedStationDoesNotWaitForETA() throws {
  var journey = try cases()[3].journey
  let index = try #require(journey.legs[0].snapshot.calls.firstIndex {
    $0.index == journey.legs[0].alightingIndex
  })
  let arrival = try #require(journey.legs[0].snapshot.calls[index].arrival?.effectiveDate)
  journey.legs[0].snapshot.calls[index].reached = true
  #expect(Projection.state(journey, now: arrival.addingTimeInterval(-600))?.phase == .completed)
  #expect(journey.completed == false)
  let reference = try ReferenceSchedule.migrate(journey.legs[0].snapshot, to: "2026-11-07")
  #expect(reference.calls.allSatisfy { $0.reached == nil })
}

@Test func passengerConfirmationsFollowLatestDepartureAndResumeAutomatically() throws {
  var j = try cases()[0].journey
  let now = j.plannedLeaveAt.addingTimeInterval(-60)
  #expect(Projection.confirmingPassengerProgress(j, to: .waiting, now: now) == nil)
  j = try #require(Projection.confirmingPassengerProgress(j, to: .onTheWay, now: now))
  #expect(Projection.confirmingPassengerProgress(j, to: .beforeDeparture, now: now) == nil)
  let boardingIndex = try #require(j.legs[0].snapshot.calls.firstIndex { $0.index == j.legs[0].boardingIndex })
  let departure = try #require(j.legs[0].boarding?.departure?.scheduledDate).addingTimeInterval(1200)
  j.legs[0].snapshot.calls[boardingIndex].departure?.estimated = Time.iso(departure)
  #expect(Projection.state(j, now: now)?.targetDate == departure)
  j = try #require(Projection.confirmingPassengerProgress(j, to: .waiting, now: now))
  #expect(Projection.state(j, now: departure.addingTimeInterval(-1))?.phase == .waiting)
  #expect(Projection.state(j, now: departure)?.phase == .riding)
  #expect(Projection.confirmingPassengerProgress(j, to: .waiting, now: departure) == nil)
  j.trackingEnded = true
  #expect(Projection.confirmingPassengerProgress(j, to: .waiting, now: now) == nil)
}

@Test func incompleteInstanceDoesNotHideAUsableReference() throws {
  let complete = try cases()[0].journey.legs[0].snapshot
  #expect(complete.hasUsableSchedule)
  // Overnight the next run is published with arrivals only: it cannot be boarded.
  var partial = complete
  partial.id = "\(complete.trainNumber):2026-11-13"
  partial.originServiceDate = "2026-11-13"
  for i in partial.calls.indices { partial.calls[i].departure = nil }
  #expect(!partial.hasUsableSchedule)
  // A week-old run of the same weekday beats a nearer run of another weekday.
  var lastWeek = complete
  lastWeek.id = "\(complete.trainNumber):2026-11-06"
  lastWeek.originServiceDate = "2026-11-06"
  var yesterday = complete
  yesterday.id = "\(complete.trainNumber):2026-11-12"
  yesterday.originServiceDate = "2026-11-12"
  let trains = [partial, yesterday, lastWeek]
  let sameDay = TrainSearchIndex.candidates(trains: trains, serviceDate: "2026-11-13", previous: nil).search("")
  #expect(sameDay.map(\.id) == [lastWeek.id])
  let future = TrainSearchIndex.candidates(trains: trains, serviceDate: "2026-11-21", previous: nil).search("")
  #expect(future.map(\.id) == [yesterday.id])
  let friday = TrainSearchIndex.candidates(trains: trains, serviceDate: "2026-11-20", previous: nil).search("")
  #expect(friday.map(\.id) == [lastWeek.id])
  // The published run wins as soon as it is complete.
  let exact = TrainSearchIndex.candidates(trains: trains, serviceDate: "2026-11-12", previous: nil).search("")
  #expect(exact.map(\.id) == [yesterday.id])
  // With nothing better, the partial run is still listed rather than hidden.
  let only = TrainSearchIndex.candidates(trains: [partial], serviceDate: "2026-11-13", previous: nil).search("")
  #expect(only.map(\.id) == [partial.id])
}

@Test func tripsCountDownOnlyInsideTheTrackingWindow() throws {
  var j = try cases()[0].journey
  let leave = j.plannedLeaveAt
  #expect(j.trackingStartsAt == leave.addingTimeInterval(-5 * 3600))
  #expect(Projection.isUpcoming(j, now: leave.addingTimeInterval(-3 * 86400)))
  #expect(Projection.isUpcoming(j, now: leave.addingTimeInterval(-5 * 3600 - 1)))
  #expect(!Projection.isUpcoming(j, now: leave.addingTimeInterval(-5 * 3600)))
  #expect(!Projection.isUpcoming(j, now: leave.addingTimeInterval(60)))
  #expect(Projection.timelineDates(j).contains(j.trackingStartsAt))
  j.trackingEnded = true
  #expect(!Projection.isUpcoming(j, now: leave.addingTimeInterval(-3 * 86400)))
}

@Test func upcomingTripsAreDescribedByCalendarDayAtTheStation() throws {
  let leave = try #require(Time.parse("2026-11-14T00:30:00-05:00"))
  func title(_ now: String) throws -> String {
    Projection.upcomingDayTitle(leave: leave, now: try #require(Time.parse(now)))
  }
  #expect(try title("2026-11-13T23:50:00-05:00") == "明天")
  #expect(try title("2026-11-12T08:00:00-05:00") == "后天")
  #expect(try title("2026-11-04T08:00:00-05:00") == "10 天后")
  #expect(try title("2026-11-14T00:10:00-05:00") == "今天")
  // The same instant is still "tomorrow" for a station three hours behind.
  #expect(Projection.upcomingDayTitle(leave: leave, now: try #require(Time.parse("2026-11-12T23:00:00-08:00")),
    zone: "America/Vancouver") == "明天")
}
