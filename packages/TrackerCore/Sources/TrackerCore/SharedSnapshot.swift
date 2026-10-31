import Foundation

#if canImport(ActivityKit) && os(iOS)
  import ActivityKit
  public struct JourneyActivityAttributes: ActivityAttributes {
    public typealias ContentState = ActivityState
    public var journeyID: String
    public init(journeyID: String) { self.journeyID = journeyID }
  }
#endif
public struct SharedSnapshot: Codable, Sendable {
  public var journey: Journey?
  public var apiBaseURL: String
  public init(journey: Journey?, apiBaseURL: String) {
    self.journey = journey
    self.apiBaseURL = apiBaseURL
  }
  public static let groupID = "group.com.junxuanb.viatracker"
  public static func read() -> SharedSnapshot? {
    #if os(iOS)
      guard
        let directory = FileManager.default.containerURL(
          forSecurityApplicationGroupIdentifier: groupID),
        let data = try? Data(contentsOf: directory.appendingPathComponent("current-journey.json"))
      else { return nil }
      return try? JSONDecoder().decode(Self.self, from: data)
    #else
      return nil
    #endif
  }
  public func write() throws {
    #if os(iOS)
      guard
        let directory = FileManager.default.containerURL(
          forSecurityApplicationGroupIdentifier: Self.groupID)
      else { return }
      let data = try JSONEncoder().encode(self)
      try data.write(
        to: directory.appendingPathComponent("current-journey.json"),
        options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    #endif
  }
}
