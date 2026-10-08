import XCTest

extension XCUIApplication {
  /// Launch arguments for a replayed run: answers come from the replay server
  /// (`PORT=8788 REPLAY=recordings/replays.json node server.mjs`), never the
  /// model, so tests don't spend model calls. The app's usual server stays
  /// live for using it by hand.
  static let replayed = ["-replayOnly", "YES", "-serverAddress", "http://localhost:8788"]
}
