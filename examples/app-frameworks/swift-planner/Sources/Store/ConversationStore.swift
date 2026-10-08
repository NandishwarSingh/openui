import Foundation
import Observation

/// One message as saved on disk.
struct StoredMessage: Codable, Identifiable, Sendable {
  enum Role: String, Codable, Sendable { case user, assistant }

  var id = UUID()
  var role: Role
  /// What the chat shows for a user turn.
  var display: String
  /// What the model sees: the user's text, or the raw response for assistant turns.
  var content: String
  /// Form and `$state` values entered in a response, as JSON.
  var state: String?
  /// File names of photos attached to a user turn (in the attachments folder).
  var images: [String] = []
  var failure: String?
  /// Results of the read-only tools an assistant turn used, as JSON by call
  /// (see `ToolResults`).
  var toolResults: [String: String]?
  /// Turns the app sends on its own (repairs) aren't shown.
  var hidden = false
}

struct Conversation: Codable, Identifiable, Sendable {
  var id = UUID()
  var title = "New plan"
  var updated = Date()
  var messages: [StoredMessage] = []
}

/// Saves conversations as JSON in Application Support, and attached photos
/// next to them. Writes are coalesced so streaming doesn't hammer the disk.
@MainActor
@Observable
final class ConversationStore {
  private(set) var conversations: [Conversation] = []
  @ObservationIgnored private var pendingSave: Task<Void, Never>?

  private static let folder: URL = {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return base.appendingPathComponent("Planner", isDirectory: true)
  }()
  private static var file: URL { folder.appendingPathComponent("conversations.json") }
  static var attachments: URL { folder.appendingPathComponent("Attachments", isDirectory: true) }

  init() {
    try? FileManager.default.createDirectory(at: Self.attachments, withIntermediateDirectories: true)
    if let data = try? Data(contentsOf: Self.file),
      let saved = try? JSONDecoder().decode([Conversation].self, from: data)
    {
      conversations = saved.sorted { $0.updated > $1.updated }
    }
  }

  func newConversation() -> Conversation {
    let conversation = Conversation()
    conversations.insert(conversation, at: 0)
    save()
    return conversation
  }

  func update(_ conversation: Conversation) {
    guard let index = conversations.firstIndex(where: { $0.id == conversation.id }) else { return }
    conversations[index] = conversation
    save()
  }

  func delete(_ id: Conversation.ID) {
    conversations.removeAll { $0.id == id }
    save()
  }

  func saveImage(_ data: Data) -> String {
    let name = UUID().uuidString + ".jpg"
    try? data.write(to: Self.attachments.appendingPathComponent(name))
    return name
  }

  func imageData(_ name: String) -> Data? {
    try? Data(contentsOf: Self.attachments.appendingPathComponent(name))
  }

  private func save() {
    pendingSave?.cancel()
    pendingSave = Task { [conversations] in
      try? await Task.sleep(for: .milliseconds(400))
      guard !Task.isCancelled, let data = try? JSONEncoder().encode(conversations) else { return }
      try? data.write(to: Self.file, options: .atomic)
    }
  }
}
