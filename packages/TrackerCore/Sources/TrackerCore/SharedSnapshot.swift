import Foundation

#if canImport(ActivityKit) && os(iOS)
  import ActivityKit
  public struct JourneyActivityAttributes: ActivityAttributes {
    public typealias ContentState = ActivityState
    public var journeyID: String
    public var testSource: String?
    public init(journeyID: String, testSource: String? = nil) {
      self.journeyID = journeyID
      self.testSource = testSource
    }
  }
#endif
public struct SharedSnapshot: Codable, Equatable, Sendable {
  public var journey: Journey?
  public var apiBaseURL: String
  public var testMode: Bool?
  public init(journey: Journey?, apiBaseURL: String, testMode: Bool? = nil) {
    self.journey = journey
    self.apiBaseURL = apiBaseURL
    self.testMode = testMode
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
      else { throw CocoaError(.fileNoSuchFile) }
      let data = try JSONEncoder().encode(self)
      try data.write(
        to: directory.appendingPathComponent("current-journey.json"),
        options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    #endif
  }
}
