import Foundation

public enum Phase: String, Codable, CaseIterable, Sendable {
  case beforeDeparture, onTheWay, waiting, riding, transferring, completed
  public var title: String {
    switch self {
    case .beforeDeparture: "出发前"
    case .onTheWay: "前往中"
    case .waiting: "候车中"
    case .riding: "行进中"
    case .transferring: "换乘中"
    case .completed: "已完成"
    }
  }
  public var symbol: String {
    switch self {
    case .beforeDeparture: "house.fill"
    case .onTheWay: "figure.walk"
    case .waiting: "clock.fill"
    case .riding: "tram.fill"
    case .transferring: "arrow.triangle.branch"
    case .completed: "checkmark.circle.fill"
    }
  }
}
public struct EventTime: Codable, Hashable, Sendable {
  public var scheduled: String
  public var estimated: String?
  public var scheduledDate: Date? { Time.parse(scheduled) }
  public var estimatedDate: Date? { estimated.flatMap(Time.parse) }
  public var effectiveDate: Date? { estimatedDate ?? scheduledDate }
  public init(scheduled: String, estimated: String? = nil) {
    self.scheduled = scheduled
    self.estimated = estimated
  }
}
public struct StationCall: Codable, Hashable, Identifiable, Sendable {
  public var index: Int
  public var code: String
  public var name: String
  public var timeZone: String
  public var arrival: EventTime?
  public var departure: EventTime?
  public var id: Int { index }
  public init(
    index: Int, code: String, name: String, timeZone: String, arrival: EventTime? = nil,
    departure: EventTime? = nil
  ) {
    self.index = index
    self.code = code
    self.name = name
    self.timeZone = timeZone
    self.arrival = arrival
    self.departure = departure
  }
}
public struct TrainPosition: Codable, Hashable, Sendable {
  public var latitude: Double
  public var longitude: Double
  public var reportedAt: String?
  public init(latitude: Double, longitude: Double, reportedAt: String? = nil) {
    self.latitude = latitude
    self.longitude = longitude
    self.reportedAt = reportedAt
  }
}
public struct TrainAlert: Codable, Hashable, Sendable {
  public var title: String
  public var body: String
  public var url: String?
}
public struct TrainSnapshot: Codable, Hashable, Identifiable, Sendable {
  public var id: String
  public var trainNumber: String
  public var originServiceDate: String
  public var rawKey: String
  public var from: String
  public var to: String
  public var departed: Bool
  public var arrived: Bool
  public var calls: [StationCall]
  public var sourceFetchedAt: String
  public var version: Int64
  public var position: TrainPosition?
  public var alerts: [TrainAlert]
  public var qualityFlags: [String]?
  public init(
    id: String, trainNumber: String, originServiceDate: String, rawKey: String, from: String,
    to: String, departed: Bool = false, arrived: Bool = false, calls: [StationCall],
    sourceFetchedAt: String, version: Int64 = 0, position: TrainPosition? = nil,
    alerts: [TrainAlert] = []
  ) {
    self.id = id
    self.trainNumber = trainNumber
    self.originServiceDate = originServiceDate
    self.rawKey = rawKey
    self.from = from
    self.to = to
    self.departed = departed
    self.arrived = arrived
    self.calls = calls
    self.sourceFetchedAt = sourceFetchedAt
    self.version = version
    self.position = position
    self.alerts = alerts
  }
}
public enum ScheduleSource: String, Codable, Sendable { case official, reference }
public enum SyncChoice: String, Codable, Sendable { case ask, keep, automatic }
public struct TrainLeg: Codable, Hashable, Identifiable, Sendable {
  public var id: String = UUID().uuidString
  public var trainNumber: String
  public var originServiceDate: String
  public var boardingCode: String
  public var boardingIndex: Int
  public var alightingCode: String
  public var alightingIndex: Int
  public var planningDeparture: Double
  public var source: ScheduleSource
  public var referenceInstanceID: String?
  public var snapshot: TrainSnapshot
  public var boarding: StationCall? {
    snapshot.calls.first { $0.index == boardingIndex && $0.code == boardingCode }
  }
  public var alighting: StationCall? {
    snapshot.calls.first { $0.index == alightingIndex && $0.code == alightingCode }
  }
  public init(
    snapshot: TrainSnapshot, boarding: StationCall, alighting: StationCall,
    source: ScheduleSource = .official, referenceInstanceID: String? = nil
  ) {
    trainNumber = snapshot.trainNumber
    originServiceDate = snapshot.originServiceDate
    boardingCode = boarding.code
    boardingIndex = boarding.index
    alightingCode = alighting.code
    alightingIndex = alighting.index
    planningDeparture = boarding.departure?.scheduledDate?.timeIntervalSince1970 ?? 0
    self.source = source
    self.referenceInstanceID = referenceInstanceID
    self.snapshot = snapshot
  }
}
public struct Journey: Codable, Hashable, Identifiable, Sendable {
  public var id: String = UUID().uuidString
  public var title: String = ""
  public var createdAt: Double = Date().timeIntervalSince1970.rounded(.down)
  public var legs: [TrainLeg]
  public var travelToStationMinutes: Int = 30
  public var currentLegIndex: Int = 0
  public var manualPhase: Phase?
  public var completed = false
  public var trackingEnded = false
  public var syncChoice: SyncChoice = .ask
  public var pendingScheduleChange = false
  public var scheduleChangePrompted = false
  public var currentLeg: TrainLeg? {
    legs.indices.contains(currentLegIndex) ? legs[currentLegIndex] : nil
  }
  public var displayTitle: String {
    title.isEmpty
      ? "\(legs.first?.boarding?.name ?? "") → \(legs.last?.alighting?.name ?? "")" : title
  }
  public var plannedLeaveAt: Date {
    Date(
      timeIntervalSince1970: (legs.first?.planningDeparture ?? 0)
        - Double(travelToStationMinutes * 60))
  }
  public init(legs: [TrainLeg], travelToStationMinutes: Int = 30) {
    self.legs = legs
    self.travelToStationMinutes = travelToStationMinutes
  }
  public mutating func advanceLeg() {
    if currentLegIndex + 1 < legs.count {
      currentLegIndex += 1
      manualPhase = nil
    } else {
      completed = true
      manualPhase = nil
    }
  }
  public mutating func chooseSync(_ automatic: Bool) {
    syncChoice = automatic ? .automatic : .keep
    pendingScheduleChange = false
    if automatic {
      for i in legs.indices {
        if legs[i].source == .official, let date = legs[i].boarding?.departure?.scheduledDate {
          legs[i].planningDeparture = date.timeIntervalSince1970.rounded(.down)
        }
      }
    }
  }
}
public struct TrainEnvelope: Codable, Sendable {
  public var schemaVersion: Int
  public var snapshotVersion: Int64
  public var sourceFetchedAt: String?
  public var sourceStatus: String
  public var availableServiceDates: [String]
  public var trains: [TrainSnapshot]
}
public enum Time {
  public static func parse(_ value: String) -> Date? {
    let f = ISO8601DateFormatter()
    if let d = f.date(from: value) { return d }
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f.date(from: value)
  }
  public static func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
  public static func format(
    _ date: Date?, zone: String = "America/Toronto", date includeDate: Bool = false
  ) -> String {
    guard let date else { return "—" }
    let f = DateFormatter()
    f.locale = Locale(identifier: "zh_Hans_CN")
    f.timeZone = TimeZone(identifier: zone)
    f.dateFormat = includeDate ? "M月d日 HH:mm" : "HH:mm"
    return f.string(from: date)
  }
  public static func serviceDate(_ date: Date, zone: String = "America/Toronto") -> String {
    let f = DateFormatter()
    f.timeZone = TimeZone(identifier: zone)
    f.dateFormat = "yyyy-MM-dd"
    f.locale = Locale(identifier: "en_US_POSIX")
    return f.string(from: date)
  }
}
