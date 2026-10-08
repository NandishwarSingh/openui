import Foundation

/// The Planner backend (`server/server.mjs`). It holds the OpenUI Cloud key and
/// the Razorpay secret, so neither ships in the app.
struct PlannerServer: Sendable {
  var baseURL: URL

  /// The server in Settings, or the build's default. On a phone, localhost is
  /// the phone itself, so Settings takes the Mac's address instead.
  static var shared: PlannerServer { PlannerServer(baseURL: address ?? defaultAddress) }

  static let defaultAddress =
    (Bundle.main.object(forInfoDictionaryKey: "PlannerServerURL") as? String)
    .flatMap(URL.init(string:)) ?? URL(string: "http://localhost:8787")!

  /// The address set in Settings, if any.
  static var address: URL? {
    get { UserDefaults.standard.string(forKey: "serverAddress").flatMap(URL.init(string:)) }
    set { UserDefaults.standard.set(newValue?.absoluteString, forKey: "serverAddress") }
  }

  /// What the server can do: chat needs the OpenUI Cloud key, payments the
  /// Razorpay keys.
  struct Health: Decodable, Sendable {
    var chat: Bool
    var payments: Bool
    /// Whether payments use Razorpay test keys, which move no money.
    var paymentsTestMode: Bool?
  }

  func health() async throws -> Health {
    var request = URLRequest(url: baseURL.appendingPathComponent("api/health"))
    request.timeoutInterval = 5
    let (data, _) = try await URLSession.shared.data(for: request)
    return try JSONDecoder().decode(Health.self, from: data)
  }

  /// A chat message in the OpenAI format: text, or text plus images.
  struct Message: Encodable, Sendable {
    var role: String
    var text: String
    /// JPEG data for images the user attached (sent as data URLs).
    var images: [Data] = []

    func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(role, forKey: .role)
      if images.isEmpty {
        try container.encode(text, forKey: .content)
      } else {
        // The model answers an empty text part with nothing, so a photo sent
        // without words goes as the image alone.
        var parts: [Part] = text.isEmpty ? [] : [Part(type: "text", text: text)]
        parts += images.map {
          Part(type: "image_url", imageURL: .init(url: "data:image/jpeg;base64,\($0.base64EncodedString())"))
        }
        try container.encode(parts, forKey: .content)
      }
    }

    private enum CodingKeys: String, CodingKey { case role, content }

    private struct Part: Encodable {
      struct ImageURL: Encodable { var url: String }
      var type: String
      var text: String?
      var imageURL: ImageURL?
      enum CodingKeys: String, CodingKey {
        case type, text
        case imageURL = "image_url"
      }
    }
  }

  struct Failure: LocalizedError {
    var errorDescription: String?
  }

  /// Streams the model's reply, yielding content deltas as they arrive.
  func streamChat(_ messages: [Message]) -> AsyncThrowingStream<String, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          var request = URLRequest(url: baseURL.appendingPathComponent("api/chat"))
          request.httpMethod = "POST"
          request.setValue("application/json", forHTTPHeaderField: "Content-Type")
          #if DEBUG
            // `-replayOnly YES`: tests never call the model by accident.
            if UserDefaults.standard.bool(forKey: "replayOnly") {
              request.setValue("1", forHTTPHeaderField: "X-Replay-Only")
            }
          #endif
          request.httpBody = try JSONEncoder().encode(["messages": messages])
          let (bytes, response) = try await URLSession.shared.bytes(for: request)
          if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            var body = Data()
            for try await byte in bytes { body.append(byte) }
            let message = (try? JSONDecoder().decode([String: String].self, from: body))?["error"]
            throw Failure(errorDescription: message ?? "The server returned HTTP \(http.statusCode).")
          }
          for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let data = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if data == "[DONE]" { break }
            // Errors after the stream starts arrive as an event of their own.
            if let failure = try? JSONDecoder().decode(ErrorEvent.self, from: Data(data.utf8)) {
              throw Failure(errorDescription: failure.error.message ?? "The model stopped with an error.")
            }
            guard let chunk = try? JSONDecoder().decode(Chunk.self, from: Data(data.utf8)) else {
              continue
            }
            if let delta = chunk.choices.first?.delta.content, !delta.isEmpty {
              continuation.yield(delta)
            }
          }
          continuation.finish()
        } catch let error as URLError where error.code == .cannotConnectToHost {
          continuation.finish(
            throwing: Failure(errorDescription: "Can't reach the Planner server. Is `node server.mjs` running?"))
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  private struct ErrorEvent: Decodable {
    struct Detail: Decodable { var message: String? }
    var error: Detail
  }

  private struct Chunk: Decodable {
    struct Choice: Decodable {
      struct Delta: Decodable { var content: String? }
      var delta: Delta
    }
    var choices: [Choice]
  }

  // MARK: Payments

  struct Order: Decodable, Sendable {
    var orderId: String
    var amount: Int
    var currency: String
    var keyId: String
  }

  func createOrder(amount: Int, currency: String, receipt: String) async throws -> Order {
    try await post("api/payments/order", ["amount": .int(amount), "currency": .string(currency), "receipt": .string(receipt)])
  }

  func verifyPayment(orderId: String, paymentId: String, signature: String) async throws -> Bool {
    struct Result: Decodable { var verified: Bool }
    let result: Result = try await post(
      "api/payments/verify",
      ["orderId": .string(orderId), "paymentId": .string(paymentId), "signature": .string(signature)])
    return result.verified
  }

  /// The payment that went through on an order, if one did, as Razorpay
  /// reports it to the server.
  func paidPayment(orderId: String) async throws -> String? {
    struct Status: Decodable {
      var paid: Bool
      var paymentId: String?
    }
    var components = URLComponents(
      url: baseURL.appendingPathComponent("api/payments/status"), resolvingAgainstBaseURL: false)!
    components.queryItems = [.init(name: "orderId", value: orderId)]
    let (data, response) = try await URLSession.shared.data(from: components.url!)
    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
      throw Failure(errorDescription: "The server couldn't check the payment.")
    }
    let status = try JSONDecoder().decode(Status.self, from: data)
    return status.paid ? status.paymentId : nil
  }

  /// Razorpay's web checkout, for macOS where the native SDK isn't available.
  func checkoutURL(_ order: Order, description: String) -> URL {
    var components = URLComponents(
      url: baseURL.appendingPathComponent("api/payments/checkout"), resolvingAgainstBaseURL: false)!
    components.queryItems = [
      .init(name: "orderId", value: order.orderId), .init(name: "amount", value: String(order.amount)),
      .init(name: "currency", value: order.currency), .init(name: "description", value: description),
    ]
    if let contact = UserDefaults.standard.string(forKey: "paymentContact") {
      components.queryItems?.append(.init(name: "contact", value: contact))
    }
    return components.url!
  }

  private enum Field: Encodable {
    case int(Int), string(String)
    func encode(to encoder: Encoder) throws {
      var container = encoder.singleValueContainer()
      switch self {
      case .int(let value): try container.encode(value)
      case .string(let value): try container.encode(value)
      }
    }
  }

  private func post<T: Decodable>(_ path: String, _ body: [String: Field]) async throws -> T {
    var request = URLRequest(url: baseURL.appendingPathComponent(path))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(body)
    let (data, response) = try await URLSession.shared.data(for: request)
    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
      let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
      throw Failure(errorDescription: message ?? "The server returned HTTP \(http.statusCode).")
    }
    return try JSONDecoder().decode(T.self, from: data)
  }
}
