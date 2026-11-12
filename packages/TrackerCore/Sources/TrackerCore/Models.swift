import Foundation

public enum Phase: String, Codable, CaseIterable, Sendable {
  case beforeDeparture, onTheWay, waiting, riding, transferring, completed
  public var title: String {
    switch self {
    case .beforeDeparture: L10n.text("出发前")
    case .onTheWay: L10n.text("前往中")
    case .waiting: L10n.text("候车中")
    case .riding: L10n.text("行进中")
    case .transferring: L10n.text("换乘中")
    case .completed: L10n.text("已完成")
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
  /// VIA's per-station ARR flag; it does not provide an actual arrival timestamp.
  public var reached: Bool?
  public var id: Int { index }
  public init(
    index: Int, code: String, name: String, timeZone: String, arrival: EventTime? = nil,
    departure: EventTime? = nil, reached: Bool? = nil
  ) {
    self.index = index
    self.code = code
    self.name = name
    self.timeZone = timeZone
    self.arrival = arrival
    self.departure = departure
    self.reached = reached
  }
}
public struct TrainPosition: Codable, Hashable, Sendable {
  public var latitude: Double
  public var longitude: Double
  public var reportedAt: String?
  public var speedKmh: Double?
  public var heading: Double?
  public init(latitude: Double, longitude: Double, reportedAt: String? = nil,
    speedKmh: Double? = nil, heading: Double? = nil) {
    self.latitude = latitude
    self.longitude = longitude
    self.reportedAt = reportedAt
    self.speedKmh = speedKmh
    self.heading = heading
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
extension TrainSnapshot {
  /// A journey needs one stop to board at and a later one to get off at. Upstream
  /// records are sometimes published without those times, typically overnight.
  public var hasUsableSchedule: Bool {
    guard let boarding = calls.first(where: { $0.departure?.scheduledDate != nil }) else { return false }
    return calls.contains { $0.index > boarding.index && $0.arrival?.scheduledDate != nil }
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
  public var notificationLanguage: String?
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
  /// Countdowns and the Live Activity begin this long before the planned time to leave.
  public static let trackingLead: TimeInterval = 5 * 3600
  public var trackingStartsAt: Date { plannedLeaveAt.addingTimeInterval(-Self.trackingLead) }
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
  // Foundation formatters are expensive. Reuse them behind a lock across the app and widget.
  private final class Formatters: @unchecked Sendable {
    let lock = NSLock()
    let iso = ISO8601DateFormatter()
    let fractional: ISO8601DateFormatter = {
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      return formatter
    }()
    let parsed = NSCache<NSString, NSDate>()
    var display: [String: DateFormatter] = [:]
    init() { parsed.countLimit = 8192 }
  }
  private static let cache = Formatters()
  public static func parse(_ value: String) -> Date? {
    if let date = cache.parsed.object(forKey: value as NSString) { return date as Date }
    cache.lock.lock()
    let result = cache.iso.date(from: value) ?? cache.fractional.date(from: value)
    cache.lock.unlock()
    if let result { cache.parsed.setObject(result as NSDate, forKey: value as NSString) }
    return result
  }
  public static func iso(_ date: Date) -> String {
    cache.lock.lock()
    defer { cache.lock.unlock() }
    return cache.iso.string(from: date)
  }
  public static func formatted(_ date: Date, zone: String, pattern: String,
    locale: String = Locale.current.identifier) -> String {
    cache.lock.lock()
    defer { cache.lock.unlock() }
    let key = "\(locale)|\(zone)|\(pattern)"
    let formatter: DateFormatter
    if let existing = cache.display[key] { formatter = existing }
    else {
      formatter = DateFormatter()
      formatter.locale = Locale(identifier: locale)
      formatter.timeZone = TimeZone(identifier: zone) ?? TimeZone(identifier: "America/Toronto")!
      formatter.dateFormat = pattern
      if cache.display.count >= 64 { cache.display.removeAll() }
      cache.display[key] = formatter
    }
    return formatter.string(from: date)
  }
  public static func format(
    _ date: Date?, zone: String = "America/Toronto", date includeDate: Bool = false
  ) -> String {
    guard let date else { return "—" }
    return formatted(date, zone: zone, pattern: includeDate ? L10n.text("M月d日 HH:mm") : "HH:mm")
  }
  public static func serviceDate(_ date: Date, zone: String = "America/Toronto") -> String {
    formatted(date, zone: zone, pattern: "yyyy-MM-dd", locale: "en_US_POSIX")
  }
}

public struct TrainSearchIndex: Sendable {
  private struct Entry: Sendable {
    var train: TrainSnapshot
    var source: String
    var text: String
  }
  private var entries: [Entry]
  public init(trains: [TrainSnapshot], reusing previous: TrainSearchIndex? = nil) {
    var cached: [String: Entry] = [:]
    for entry in previous?.entries ?? [] { cached[entry.train.id] = entry }
    entries = trains.sorted {
      if $0.trainNumber == $1.trainNumber { return $0.originServiceDate > $1.originServiceDate }
      return $0.trainNumber.localizedStandardCompare($1.trainNumber) == .orderedAscending
    }.map { train in
      let names = train.calls.map { "\($0.name) \($0.code)" }.joined(separator: " ")
      let source = "VIA \(train.trainNumber) \(train.from) \(train.to) \(names)"
      let text = cached[train.id].flatMap { $0.source == source ? $0.text : nil }
        ?? Self.normalized(source)
      return Entry(train: train, source: source, text: text)
    }
  }
  public static func normalized(_ value: String) -> String {
    value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
      locale: Locale(identifier: "en_US_POSIX"))
      .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
  }
  public func search(_ query: String, serviceDate: String? = nil) -> [TrainSnapshot] {
    let terms = Self.normalized(query)
      .replacingOccurrences(of: "quebec city", with: "quebec")
      .replacingOccurrences(of: "ville de quebec", with: "quebec").split(separator: " ")
    return entries.filter { entry in
      (serviceDate == nil || entry.train.originServiceDate == serviceDate)
        && terms.allSatisfy { entry.text.contains($0) }
    }.map(\.train)
  }
  public static func candidates(trains: [TrainSnapshot], serviceDate: String,
    previous: TrainLeg?, reusing index: TrainSearchIndex? = nil) -> TrainSearchIndex {
    let groups = Dictionary(grouping: trains, by: \.trainNumber)
    let selected = groups.values.compactMap { values -> TrainSnapshot? in
      // An instance published without boardable times must not hide a complete
      // run of the same train that can lend its timetable to this date.
      let usable = values.filter(\.hasUsableSchedule)
      return usable.first { $0.originServiceDate == serviceDate }
        ?? ReferenceSchedule.bestReference(usable, for: serviceDate)
        ?? values.first { $0.originServiceDate == serviceDate }
    }.filter { train in
      guard let previous else { return true }
      guard let arrival = previous.alighting?.arrival?.scheduledDate,
        let snapshot = try? (train.originServiceDate == serviceDate ? train
          : ReferenceSchedule.migrate(train, to: serviceDate, repeatedTime: .first)) else { return false }
      return snapshot.calls.contains { call in
        call.code == previous.alightingCode && (call.departure?.scheduledDate.map { $0 >= arrival } ?? false)
          && snapshot.calls.contains { $0.index > call.index && $0.arrival != nil }
      }
    }
    return TrainSearchIndex(trains: selected, reusing: index)
  }
}
