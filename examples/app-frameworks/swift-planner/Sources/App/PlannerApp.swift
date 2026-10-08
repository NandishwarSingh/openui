import SwiftUI

@main
struct PlannerApp: App {
  init() {
    #if DEBUG
      HangWatchdog.start()
    #endif
    // `-dumpPrompt YES` prints the system prompt and quits (for checking it).
    if UserDefaults.standard.bool(forKey: "dumpPrompt") {
      print(PlannerLibrary.systemPrompt())
      exit(0)
    }
  }

  var body: some Scene {
    WindowGroup {
      RootView()
    }
    #if os(macOS)
      .defaultSize(width: 1100, height: 780)
    #endif
  }
}
