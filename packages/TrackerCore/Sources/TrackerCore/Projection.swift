import Foundation

public struct ActivityState: Codable, Hashable, Sendable {
  public var phase: Phase
  public var trainNumber: String
  public var destination: String
  public var origin: String
  public var targetEpoch: Double
  public var scheduledEpoch: Double
  public var sourceFetchedEpoch: Double
  public var validUntilEpoch: Double
  public var progress: Double
  public var currentLegIndex: Int
  public var legCount: Int
  public var waitingForUpdate: Bool
  public var reference: Bool
  public var targetIsEstimate: Bool
  public var nextTrainNumber: String?
  public var nextDepartureEpoch: Double?
  public var connectionMinutes: Int?
  public var targetDate: Date { Date(timeIntervalSince1970: targetEpoch) }
  public var countdownLabel: String {
    switch phase {
    case .beforeDeparture: "距计划出门"
    case .onTheWay: "距官方计划发车"
    case .waiting: targetIsEstimate ? "距预计发车" : "距计划发车"
    case .riding: "距 \(destination) \(targetIsEstimate ? "预计" : "计划")到达"
    case .transferring: "距下一段计划发车"
    case .completed: "已到达 \(destination)"
    }
  }
}
public enum Projection {
  public static func state(_ j: Journey, now: Date = Date()) -> ActivityState? {
    guard !j.legs.isEmpty else { return nil }
    let i = min(max(j.currentLegIndex, 0), j.legs.count - 1)
    let l = j.legs[i]
    let t = now.timeIntervalSince1970
    let dep = l.boarding?.departure?.scheduledDate?.timeIntervalSince1970 ?? l.planningDeparture
    let estDep = l.boarding?.departure?.estimatedDate?.timeIntervalSince1970 ?? dep
    let arr = l.alighting?.arrival?.scheduledDate?.timeIntervalSince1970 ?? dep
    let estArr = l.alighting?.arrival?.estimatedDate?.timeIntervalSince1970 ?? arr
    let leave = j.plannedLeaveAt.timeIntervalSince1970
    let phase: Phase =
      j.completed
      ? .completed
      : j.manualPhase
        ?? (i > 0
          ? .transferring : t < leave ? .beforeDeparture : t < dep - 900 ? .onTheWay : .waiting)
    let target: Double =
      switch phase {
      case .beforeDeparture: leave
      case .onTheWay, .transferring: dep
      case .waiting: estDep
      case .riding, .completed: estArr
      }
    let fetched = Time.parse(l.snapshot.sourceFetchedAt)?.timeIntervalSince1970 ?? 0
    let next = j.legs.indices.contains(i + 1) ? j.legs[i + 1] : nil
    let nextDep = next?.boarding?.departure?.scheduledDate?.timeIntervalSince1970
    return ActivityState(
      phase: phase, trainNumber: l.trainNumber, destination: l.alighting?.name ?? l.alightingCode,
      origin: l.boarding?.name ?? l.boardingCode, targetEpoch: target,
      scheduledEpoch: phase == .riding || phase == .completed ? arr : dep,
      sourceFetchedEpoch: fetched, validUntilEpoch: fetched + 600,
      progress: min(1, max(0, (t - estDep) / max(1, estArr - estDep))), currentLegIndex: i,
      legCount: j.legs.count, waitingForUpdate: phase != .completed && t >= target,
      reference: l.source == .reference,
      targetIsEstimate: phase == .riding
        ? l.alighting?.arrival?.estimatedDate != nil
        : phase == .waiting && l.boarding?.departure?.estimatedDate != nil,
      nextTrainNumber: next?.trainNumber,
      nextDepartureEpoch: nextDep, connectionMinutes: nextDep.map { Int(($0 - estArr) / 60) })
  }
  public static func reconcile(_ journey: Journey, snapshots: [TrainSnapshot]) -> Journey {
    var j = journey
    for i in j.legs.indices {
      let leg = j.legs[i]
      guard
        let latest = snapshots.first(where: {
          $0.trainNumber == leg.trainNumber && $0.originServiceDate == leg.originServiceDate
        }), latest.version >= leg.snapshot.version,
        let boarding = latest.calls.first(where: {
          $0.index == leg.boardingIndex && $0.code == leg.boardingCode
        }), let dep = boarding.departure?.scheduledDate,
        let alighting = latest.calls.first(where: {
          $0.index == leg.alightingIndex && $0.code == leg.alightingCode
        }), alighting.arrival != nil, boarding.index < alighting.index
      else { continue }
      j.legs[i].snapshot = latest
      j.legs[i].source = .official
      if j.syncChoice == .automatic {
        j.legs[i].planningDeparture = dep.timeIntervalSince1970
      } else if leg.source == .reference
        && abs(dep.timeIntervalSince1970 - leg.planningDeparture) >= 1 && !j.scheduleChangePrompted
      {
        j.pendingScheduleChange = true
        j.scheduleChangePrompted = true
      }
    }
    return j
  }
}

public enum ReferenceError: Error, LocalizedError {
  case invalidDate, ambiguousTime, missingStations
  public var errorDescription: String? {
    switch self {
    case .invalidDate: "日期无效"
    case .ambiguousTime: "该日期存在夏令时时间歧义，请选择其他日期或等待正式时刻。"
    case .missingStations: "没有可借用的完整乘车区间。"
    }
  }
}
public enum ReferenceSchedule {
  public enum RepeatedTime: Sendable { case first, last }
  /// Copy station-local wall times and calendar-day offsets; never copy estimates or running evidence.
  public static func migrate(
    _ snapshot: TrainSnapshot, to targetServiceDate: String, repeatedTime: RepeatedTime? = nil
  ) throws
    -> TrainSnapshot
  {
    let dateFormat = DateFormatter()
    dateFormat.locale = Locale(identifier: "en_US_POSIX")
    dateFormat.timeZone = TimeZone(secondsFromGMT: 0)
    dateFormat.dateFormat = "yyyy-MM-dd"
    dateFormat.isLenient = false
    guard let origin = dateFormat.date(from: snapshot.originServiceDate),
      let target = dateFormat.date(from: targetServiceDate)
    else { throw ReferenceError.invalidDate }
    let utc = Calendar(identifier: .gregorian)
    var utcCalendar = utc
    utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let days = utcCalendar.dateComponents([.day], from: origin, to: target).day ?? 0
    var result = snapshot
    result.id = "\(snapshot.trainNumber):\(targetServiceDate)"
    result.originServiceDate = targetServiceDate
    result.departed = false
    result.arrived = false
    result.position = nil
    result.alerts = []
    result.version = 0
    result.calls = try snapshot.calls.map { call in
      guard let zone = TimeZone(identifier: call.timeZone) else { throw ReferenceError.invalidDate }
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = zone
      func moved(_ event: EventTime?) throws -> EventTime? {
        guard let event, let original = event.scheduledDate else { return nil }
        let local = calendar.dateComponents(
          [.year, .month, .day, .hour, .minute, .second], from: original)
        var noon = local
        noon.hour = 12
        noon.minute = 0
        noon.second = 0
        guard let originalNoon = calendar.date(from: noon),
          let targetNoon = calendar.date(byAdding: .day, value: days, to: originalNoon)
        else { throw ReferenceError.invalidDate }
        var wanted = calendar.dateComponents([.year, .month, .day], from: targetNoon)
        wanted.hour = local.hour
        wanted.minute = local.minute
        wanted.second = local.second
        let start = calendar.startOfDay(for: targetNoon).addingTimeInterval(-1)
        guard
          let first = calendar.nextDate(
            after: start, matching: wanted, matchingPolicy: .strict, repeatedTimePolicy: .first,
            direction: .forward),
          let last = calendar.nextDate(
            after: start, matching: wanted, matchingPolicy: .strict, repeatedTimePolicy: .last,
            direction: .forward), calendar.isDate(first, inSameDayAs: targetNoon),
          calendar.isDate(last, inSameDayAs: targetNoon)
        else { throw ReferenceError.ambiguousTime }
        if first != last && repeatedTime == nil { throw ReferenceError.ambiguousTime }
        return EventTime(scheduled: Time.iso(repeatedTime == .last ? last : first))
      }
      var c = call
      c.arrival = try moved(call.arrival)
      c.departure = try moved(call.departure)
      return c
    }
    return result
  }
}
