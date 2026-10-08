import OpenUISwiftUI

/// The results of the read-only tools a response used, kept with its message.
/// A reopened conversation shows what it showed before instead of asking the
/// tools again, which may answer differently, slowly, or not at all offline.
/// A query that runs again while the app is open, like one a Mutation
/// refreshes, still calls its tool.
@MainActor
final class ToolResults {
  private var results: [String: String]
  private var used: Set<String> = []
  private let save: (_ key: String, _ json: String) -> Void

  init(_ results: [String: String], save: @escaping (_ key: String, _ json: String) -> Void) {
    self.results = results
    self.save = save
  }

  /// A call's key: the tool and its arguments, which keep the order they
  /// have in the response.
  nonisolated static func key(_ tool: String, _ arguments: OpenUIObject) -> String {
    "\(tool) \(JSON.stringify(.object(arguments)))"
  }

  /// The saved result for a call, the first time it's asked for.
  func saved(_ key: String) -> OpenUIValue? {
    guard used.insert(key).inserted, let json = results[key] else { return nil }
    return try? JSON.parse(json)
  }

  func keep(_ value: OpenUIValue, for key: String) {
    used.insert(key)
    let json = JSON.stringify(value)
    guard results[key] != json else { return }
    results[key] = json
    save(key, json)
  }
}
