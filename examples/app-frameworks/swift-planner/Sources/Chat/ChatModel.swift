import Foundation
import Observation
import OpenUISwiftUI

/// A message in the open conversation, plus its streaming state.
struct ChatMessage: Identifiable {
  var stored: StoredMessage
  var isStreaming = false

  var id: UUID { stored.id }
  var role: StoredMessage.Role { stored.role }
  var state: OpenUIObject {
    get { stored.state.flatMap { try? JSON.parse($0).objectValue } ?? OpenUIObject() }
    set { stored.state = newValue.isEmpty ? nil : JSON.stringify(.object(newValue)) }
  }
}

/// One conversation: sends turns to the model through the Planner server,
/// paces the streamed text, and turns component actions into messages the way
/// react-ui's chat does (Cloud's content/context format).
@MainActor
@Observable
final class ChatModel {
  private(set) var messages: [ChatMessage]
  private(set) var title: String
  /// Bumped when a message is sent and when a response finishes, for haptics.
  private(set) var sentCount = 0
  private(set) var finishedCount = 0
  var isStreaming: Bool { messages.last?.isStreaming == true }
  var visibleMessages: [ChatMessage] { messages.filter { !$0.stored.hidden } }

  let id: Conversation.ID
  @ObservationIgnored private let store: ConversationStore
  @ObservationIgnored private var task: Task<Void, Never>?
  @ObservationIgnored private let pacer = TextPacer()

  init(_ conversation: Conversation, store: ConversationStore) {
    id = conversation.id
    title = conversation.title
    messages = conversation.messages.map { ChatMessage(stored: $0) }
    self.store = store
  }

  func send(_ text: String, images: [Data] = []) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty || !images.isEmpty else { return }
    var message = StoredMessage(role: .user, display: trimmed, content: trimmed)
    message.images = images.map(store.saveImage)
    respond(to: message)
  }

  /// Handles a component action the way react-ui's GenUIAssistantMessage does.
  func handle(_ event: ActionEvent, openURL: (URL) -> Void) {
    switch event.type {
    case BuiltinActionType.continueConversation:
      var context: [OpenUIValue] = [.string("User clicked: \(event.humanFriendlyMessage)")]
      if let formState = event.formState { context.append(.object(formState)) }
      let content =
        Wire.content(event.humanFriendlyMessage) + Wire.context(JSON.stringify(.array(context)))
      respond(to: StoredMessage(role: .user, display: event.humanFriendlyMessage, content: content))
    case BuiltinActionType.openUrl:
      if let url = event.params["url"]?.stringValue.flatMap(URL.init(string:)) { openURL(url) }
    default:
      break
    }
  }

  /// Tells the model about a payment made with a PayButton, as the user's next
  /// message (react-ui's content/context format, like an action).
  func reportPayment(_ receipt: PaymentReceipt, for description: String) {
    let display = "Paid \(receipt.formattedAmount) for \(description)"
    let details: OpenUIValue = [
      "payment": "succeeded", "paymentId": .string(receipt.paymentId),
      "orderId": .string(receipt.orderId), "amount": .string(receipt.formattedAmount),
      "for": .string(description),
    ]
    let content = Wire.content(display) + Wire.context(JSON.stringify(.array([details])))
    respond(to: StoredMessage(role: .user, display: display, content: content))
  }

  func image(named name: String) -> Data? { store.imageData(name) }

  func updateState(_ state: OpenUIObject, of id: ChatMessage.ID) {
    guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
    messages[index].state = state
    persist()
  }

  /// Keeps a tool's result with the response that called it.
  func saveToolResult(_ json: String, for key: String, of id: ChatMessage.ID) {
    guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
    var results = messages[index].stored.toolResults ?? [:]
    results[key] = json
    messages[index].stored.toolResults = results
    persist()
  }

  func stop() {
    task?.cancel()
  }

  /// Sends the last user message again after a failed response.
  func retry() {
    guard !isStreaming, let failed = messages.last, failed.role == .assistant,
      failed.stored.failure != nil,
      let userIndex = messages.lastIndex(where: { $0.role == .user && !$0.stored.hidden })
    else { return }
    let user = messages[userIndex].stored
    messages.removeSubrange(userIndex...)
    respond(to: user)
  }

  // MARK: Sending

  private func respond(to message: StoredMessage) {
    guard !isStreaming else { return }
    // Most answers need the user's location; ask for it while this one streams.
    ToolRunner.shared.prepareLocation()
    messages.append(ChatMessage(stored: message))
    if !message.hidden { sentCount += 1 }
    if title == "New plan", !message.display.isEmpty { title = String(message.display.prefix(48)) }
    let history = [PlannerServer.Message(role: "system", text: PlannerLibrary.systemPrompt())]
      + Self.history(messages, imageData: store.imageData)
    let server = PlannerServer.shared
    startResponse { emit in
      for try await delta in server.streamChat(history) { emit(delta) }
    }
  }

  /// The conversation as the model should see it:
  /// - failed answers are left out (an empty assistant message makes the model
  ///   return nothing for the whole conversation, and a half-finished one is
  ///   noise), and so are empty turns;
  /// - user turns left next to each other are merged, since some models want
  ///   turns to alternate;
  /// - only the latest photos are sent again; older ones become a note, so the
  ///   request doesn't grow with every photo in the conversation.
  static func history(_ messages: [ChatMessage], imageData: (String) -> Data?)
    -> [PlannerServer.Message]
  {
    let recentPhotoTurns = Set(
      messages.filter { $0.role == .user && !$0.stored.images.isEmpty }.suffix(2).map(\.id))
    var history: [PlannerServer.Message] = []
    for turn in messages {
      switch turn.role {
      case .assistant:
        guard !turn.stored.content.isEmpty, turn.stored.failure == nil else { continue }
        let state = turn.stored.state.map { Wire.context("[\($0)]") } ?? ""
        history.append(PlannerServer.Message(role: "assistant", text: turn.stored.content + state))
      case .user:
        let photos = recentPhotoTurns.contains(turn.id) ? turn.stored.images.compactMap(imageData) : []
        var text = turn.stored.content
        if photos.isEmpty, !turn.stored.images.isEmpty {
          text += text.isEmpty ? "(I shared a photo here.)" : "\n(I shared a photo here.)"
        } else if text.isEmpty, !photos.isEmpty {
          // The model fails on a photo without text (an empty answer, or a
          // provider error), so a photo sent on its own gets a caption.
          text = "Here's a photo."
        }
        guard !text.isEmpty || !photos.isEmpty else { continue }
        if let last = history.last, last.role == "user" {
          history[history.count - 1] = PlannerServer.Message(
            role: "user", text: [last.text, text].filter { !$0.isEmpty }.joined(separator: "\n\n"),
            images: last.images + photos)
        } else {
          history.append(PlannerServer.Message(role: "user", text: text, images: photos))
        }
      }
    }
    return history
  }

  /// Adds a streaming assistant message and feeds it through the pacer:
  /// network chunks arrive in bursts, the text appears at a steady rate.
  private func startResponse(
    _ source: @escaping @MainActor (_ emit: (String) -> Void) async throws -> Void
  ) {
    messages.append(
      ChatMessage(stored: StoredMessage(role: .assistant, display: "", content: ""), isStreaming: true))
    let id = messages[messages.count - 1].id
    pacer.start { [weak self] text in self?.append(text, to: id) }
    task = Task {
      var failure: String?
      do {
        try await source { [pacer] delta in pacer.push(delta) }
      } catch is CancellationError {
      } catch {
        failure = error.localizedDescription
      }
      if Task.isCancelled { pacer.cancel() } else { await pacer.drain() }
      if failure == nil, !Task.isCancelled, messages.last(where: { $0.id == id })?.stored.content.isEmpty == true {
        failure = "No answer came back."
      }
      finish(id, failure: failure)
    }
  }

  private func append(_ text: String, to id: ChatMessage.ID) {
    guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
    messages[index].stored.content += text
  }

  private func finish(_ id: ChatMessage.ID, failure: String?) {
    guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
    messages[index].isStreaming = false
    messages[index].stored.failure = failure
    finishedCount += 1
    persist()
  }

  private func persist() {
    store.update(
      Conversation(id: id, title: title, updated: Date(), messages: messages.map(\.stored)))
  }
}

/// Releases streamed text at a steady pace. Network chunks arrive in bursts
/// (dozens of characters every few hundred milliseconds); revealing a few
/// characters every tick, faster when a backlog builds up, makes the response
/// grow smoothly instead of in jumps.
@MainActor
final class TextPacer {
  private var buffer: [Character] = []
  private var reveal: ((String) -> Void)?
  private var ticker: Task<Void, Never>?

  func start(_ reveal: @escaping (String) -> Void) {
    cancel()
    self.reveal = reveal
    ticker = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(33))
        self?.tick()
      }
    }
  }

  func push(_ text: String) {
    buffer.append(contentsOf: text)
  }

  /// Waits until everything pushed so far has been revealed.
  func drain() async {
    while !buffer.isEmpty && ticker != nil {
      try? await Task.sleep(for: .milliseconds(33))
    }
    cancel()
  }

  func cancel() {
    ticker?.cancel()
    ticker = nil
    if !buffer.isEmpty { reveal?(String(buffer)) }
    buffer.removeAll()
    reveal = nil
  }

  private func tick() {
    guard !buffer.isEmpty else { return }
    // About 90 characters a second, catching up within ~0.5s of a backlog.
    let count = min(buffer.count, max(3, buffer.count / 15))
    reveal?(String(buffer.prefix(count)))
    buffer.removeFirst(count)
  }
}

/// OpenUI Cloud's inline markers (react-ui's sentinelParser).
enum Wire {
  static func content(_ text: String) -> String { "]]>openui:content\n\(text)" }
  static func context(_ json: String) -> String { "\n]]>openui:context\n\(json)" }

  /// The program part of a response: after a content header if there is one,
  /// before any context section, without the end marker.
  static func program(_ raw: String) -> String {
    var text = raw.replacingOccurrences(of: "]]>openui:end", with: "")
    if let header = text.range(of: "]]>openui:content", options: .backwards) {
      text = String(text[header.upperBound...])
      if let newline = text.firstIndex(of: "\n") {
        text = String(text[text.index(after: newline)...])
      } else {
        text = ""
      }
    }
    if let context = text.range(of: "]]>openui:context") {
      text = String(text[..<context.lowerBound])
    }
    return text
  }
}
