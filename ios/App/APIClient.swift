import Foundation
import Security
import CryptoKit
import TrackerCore

struct InstallationIdentity: Codable, Sendable {
  var id: String
  var credential: String
  static func load(namespace: String = "installation") throws -> Self {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "com.junxuanb.viatracker.installation",
      kSecAttrAccount as String: namespace, kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecSuccess, let data = result as? Data {
      return try JSONDecoder().decode(Self.self, from: data)
    }
    guard status == errSecItemNotFound else {
      throw APIClient.Failure.message("无法读取本机凭证，请解锁设备后重试。")
    }
    var bytes = [UInt8](repeating: 0, count: 32)
    guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
      throw APIClient.Failure.message("无法创建本机凭证。")
    }
    let value = Self(
      id: UUID().uuidString, credential: bytes.map { String(format: "%02x", $0) }.joined())
    var insert = query
    insert.removeValue(forKey: kSecReturnData as String)
    insert.removeValue(forKey: kSecMatchLimit as String)
    insert[kSecValueData as String] = try JSONEncoder().encode(value)
    insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else {
      throw APIClient.Failure.message("无法保存本机凭证。")
    }
    return value
  }
}
struct SubscriptionResponse: Codable, Sendable {
  var id: String
  var revision: Int
  var journey: Journey
}
struct SubscriptionList: Codable, Sendable { var subscriptions: [SubscriptionResponse] }
struct RemoteActivitySession: Codable, Sendable {
  var id: String
  var token: String
  var startedAt: Int
  var revision: Int
  var testSource: String? = nil
}
/// Asks the server to start the Live Activity when the journey's tracking window opens.
struct RemoteActivityStart: Codable, Sendable { var testSource: String? = nil }
struct SubscriptionRequest: Codable, Sendable {
  var journey: Journey
  var revision: Int
  var activity: RemoteActivitySession?
  var autoStart: RemoteActivityStart? = nil
}

actor APIClient {
  enum Failure: Error, LocalizedError {
    case http(Int, String)
    case message(String)
    var errorDescription: String? {
      switch self {
      case .http(let status, let code):
        status == 409 ? "数据正在同步，请重试。" : "暂时无法更新（\(status) · \(code)）"
      case .message(let message): message
      }
    }
  }
  let baseURL: URL
  private let identityNamespace: String
  private var shuttingDown = false
  private var inFlight = 0
  private var identity: InstallationIdentity?
  private var registered = false
  private var etag: String?
  private var writeRetryAt: Date?
  init(baseURL: URL, identityNamespace: String = "installation") {
    self.baseURL = baseURL
    self.identityNamespace = identityNamespace
  }
  private func request(
    _ path: String, method: String = "GET", body: Data? = nil, authenticated: Bool = false,
    duringShutdown: Bool = false
  ) async throws -> (Data, HTTPURLResponse) {
    guard !shuttingDown || duringShutdown else { throw CancellationError() }
    inFlight += 1
    defer { inFlight -= 1 }
    if method != "GET", let writeRetryAt, Date() < writeRetryAt {
      throw Failure.http(429, "rate_limited")
    }
    guard let url = URL(string: path, relativeTo: baseURL) else { throw Failure.message("服务地址无效") }
    // ETag and the persisted snapshot are managed here; avoid a second cache
    // returning an older body or hiding the server's conditional response.
    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
    request.httpMethod = method
    request.timeoutInterval = duringShutdown ? 5 : 25
    request.httpBody = body
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if authenticated {
      if identity == nil { identity = try InstallationIdentity.load(namespace: identityNamespace) }
      if let identity {
        request.setValue(
          "Bearer \(identity.id):\(identity.credential)", forHTTPHeaderField: "Authorization")
      }
    }
    if path == "/v1/trains", let etag {
      request.setValue(etag, forHTTPHeaderField: "If-None-Match")
    }
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw Failure.message("服务响应无效") }
    guard (200..<300).contains(http.statusCode) || http.statusCode == 304 else {
      let error = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
      let code = (error?["error"] as? [String: Any])?["code"] as? String ?? "unknown"
      if http.statusCode == 401 { registered = false }
      if http.statusCode == 429 && method != "GET" {
        let seconds = Double(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 60
        writeRetryAt = Date().addingTimeInterval(min(300, max(1, seconds)))
      }
      throw Failure.http(http.statusCode, code)
    }
    return (data, http)
  }
  func invalidateTrainCache() { etag = nil }
  func trains() async throws -> (envelope: TrainEnvelope, data: Data)? {
    let (data, response) = try await request("/v1/trains")
    if response.statusCode == 304 { return nil }
    let envelope = try JSONDecoder().decode(TrainEnvelope.self, from: data)
    guard envelope.schemaVersion == 1 else { throw Failure.message("服务版本已更新，请更新 App。") }
    guard !envelope.trains.isEmpty || envelope.sourceStatus != "healthy" else {
      throw Failure.message("列车数据暂时为空，保留最近有效数据。")
    }
    etag = response.value(forHTTPHeaderField: "ETag")
    // Persist the already validated response without encoding the whole feed on the UI actor.
    return (envelope, data)
  }
  func register(environment: String) async throws {
    if registered { return }
    if identity == nil { identity = try InstallationIdentity.load(namespace: identityNamespace) }
    guard let identity else { return }
    struct Registration: Encodable {
      var id: String
      var credential: String
      var environment: String
    }
    _ = try await request(
      "/v1/installations", method: "POST",
      body: JSONEncoder().encode(
        Registration(id: identity.id, credential: identity.credential, environment: environment)))
    registered = true
  }
  func sync(_ body: SubscriptionRequest) async throws -> SubscriptionResponse {
    let (data, _) = try await request(
      "/v1/subscriptions", method: "POST", body: JSONEncoder().encode(body), authenticated: true)
    return try JSONDecoder().decode(SubscriptionResponse.self, from: data)
  }
  func subscriptions() async throws -> [SubscriptionResponse] {
    let (data, _) = try await request("/v1/subscriptions", authenticated: true)
    return try JSONDecoder().decode(SubscriptionList.self, from: data).subscriptions
  }
  func delete(_ id: String) async throws {
    _ = try await request("/v1/subscriptions/\(id)", method: "DELETE", authenticated: true)
  }
  func pushToken(_ token: String?, environment: String) async throws {
    struct Registration: Encodable {
      var pushToken: String?
      var environment: String
    }
    _ = try await request(
      "/v1/installations", method: "PATCH",
      body: JSONEncoder().encode(Registration(pushToken: token, environment: environment)),
      authenticated: true)
  }
  func activityStartToken(_ token: String, environment: String) async throws {
    _ = try await request(
      "/v1/activity-start-token", method: "PUT",
      body: JSONEncoder().encode(["token": token, "environment": environment]), authenticated: true)
  }
  func configureWidgetPush(environment: String) throws {
    guard !shuttingDown, let identity else { return }
    let registration = WidgetRegistration(apiBaseURL: baseURL.absoluteString,
      authorization: "Bearer \(identity.id):\(identity.credential)", environment: environment)
    if WidgetRegistration.read() != registration { try registration.write() }
  }
  func testDeviceCode() throws -> String? {
    guard let identity else { return nil }
    return SHA256.hash(data: Data(identity.id.utf8)).prefix(4).map { String(format: "%02X", $0) }.joined()
  }
  func validatePublicTestEnvironment() async throws {
    let (data, _) = try await request("/health")
    struct Health: Decodable { var environment: String?; var remotePush: Bool? }
    let health = try JSONDecoder().decode(Health.self, from: data)
    guard health.environment == "test", health.remotePush == true else {
      throw Failure.message("这个地址不是公网测试环境。")
    }
  }
  func suspend(journeyIDs: [String], publicTest: Bool, remotePush: Bool, environment: String) async {
    shuttingDown = true
    // Let an already-started upload finish before removing its subscription.
    while inFlight > 0 { try? await Task.sleep(for: .milliseconds(30)) }
    guard remotePush else { return }
    if identity == nil { identity = try? InstallationIdentity.load(namespace: identityNamespace) }
    guard identity != nil else { return }
    _ = try? await request("/v1/widget-token", method: "DELETE", authenticated: true, duringShutdown: true)
    _ = try? await request("/v1/activity-start-token", method: "DELETE", authenticated: true, duringShutdown: true)
    if publicTest {
      _ = try? await request("/v1/test-device", method: "DELETE", authenticated: true, duringShutdown: true)
      return
    }
    for id in journeyIDs {
      _ = try? await request("/v1/subscriptions/\(id)", method: "DELETE", authenticated: true, duringShutdown: true)
    }
    struct Token: Encodable { var pushToken: String? = nil; var environment: String }
    if let body = try? JSONEncoder().encode(Token(environment: environment)) {
      _ = try? await request("/v1/installations", method: "PATCH", body: body, authenticated: true, duringShutdown: true)
    }
  }
}
