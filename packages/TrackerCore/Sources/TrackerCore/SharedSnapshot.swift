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
  public var visibleUntil: Date? = nil
  public init(journey: Journey?, apiBaseURL: String, testMode: Bool? = nil, visibleUntil: Date? = nil) {
    self.journey = journey
    self.apiBaseURL = apiBaseURL
    self.testMode = testMode
    self.visibleUntil = visibleUntil
  }
  public static let groupID = "group.com.junxuanb.viatracker"
  public static func read(widgetCache: Bool = false) -> SharedSnapshot? {
    #if os(iOS)
      guard
        let directory = FileManager.default.containerURL(
          forSecurityApplicationGroupIdentifier: groupID),
        let data = try? Data(contentsOf: directory.appendingPathComponent(widgetCache ? "widget-journey.json" : "current-journey.json"))
      else { return nil }
      return try? JSONDecoder().decode(Self.self, from: data)
    #else
      return nil
    #endif
  }
  public func write(widgetCache: Bool = false) throws {
    #if os(iOS)
      guard
        let directory = FileManager.default.containerURL(
          forSecurityApplicationGroupIdentifier: Self.groupID)
      else { throw CocoaError(.fileNoSuchFile) }
      let data = try JSONEncoder().encode(self)
      try data.write(
        to: directory.appendingPathComponent(widgetCache ? "widget-journey.json" : "current-journey.json"),
        options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    #endif
  }
}

/// Shared only with our widget extension; never embedded in a timeline or notification.
public struct WidgetRegistration: Codable, Equatable, Sendable {
  public var apiBaseURL: String
  public var authorization: String
  public var environment: String
  public init(apiBaseURL: String, authorization: String, environment: String) {
    self.apiBaseURL = apiBaseURL; self.authorization = authorization; self.environment = environment
  }
  private static var file: URL? {
    #if os(iOS)
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedSnapshot.groupID)?
      .appendingPathComponent("widget-registration.json")
    #else
    nil
    #endif
  }
  public static func read() -> Self? {
    guard let file, let data = try? Data(contentsOf: file) else { return nil }
    return try? JSONDecoder().decode(Self.self, from: data)
  }
  public func write() throws {
    #if os(iOS)
    guard let file = Self.file else { return }
    try JSONEncoder().encode(self).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    #endif
  }
  public static func clear() { if let file { try? FileManager.default.removeItem(at: file) } }
  public func register(_ token: Data) async {
    #if os(iOS)
    guard Self.read() == self, let url = URL(string: "/v1/widget-token", relativeTo: URL(string: apiBaseURL)) else { return }
    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
    request.httpMethod = "PUT"
    request.setValue(authorization, forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let hex = token.map { String(format: "%02x", $0) }.joined()
    request.httpBody = try? JSONEncoder().encode(["token": hex, "environment": environment])
    _ = try? await URLSession.shared.data(for: request)
    #endif
  }
}
