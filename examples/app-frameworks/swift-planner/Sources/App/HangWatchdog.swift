#if DEBUG
  import Foundation

  /// Catches freezes in debug builds: a background thread pings the main
  /// thread every 100 ms, and any reply that takes longer than 250 ms is
  /// logged with how long the main thread was stuck (also while it is still
  /// stuck, since a freeze may never end). The log is
  /// Library/Caches/hangs.log (cleared at launch), so a test run or a manual
  /// session can be checked for stalls afterwards.
  enum HangWatchdog {
    static let log = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("hangs.log")

    static func start() {
      try? FileManager.default.removeItem(at: log)
      FileManager.default.createFile(atPath: log.path, contents: nil)
      let thread = Thread {
        while true {
          let reply = DispatchSemaphore(value: 0)
          let sent = Date()
          DispatchQueue.main.async { reply.signal() }
          if reply.wait(timeout: .now() + 0.25) == .timedOut {
            // A freeze may never end, so report it while it lasts too: at one
            // second, then every five.
            var next: TimeInterval = 1
            while reply.wait(timeout: .now() + 0.25) == .timedOut {
              let stuck = Date().timeIntervalSince(sent)
              if stuck >= next {
                record(stuck, ongoing: true)
                next = next == 1 ? 5 : next + 5
              }
            }
            record(Date().timeIntervalSince(sent), ongoing: false)
          }
          Thread.sleep(forTimeInterval: 0.1)
        }
      }
      thread.name = "HangWatchdog"
      thread.qualityOfService = .userInteractive
      thread.start()
    }

    private static func record(_ stall: TimeInterval, ongoing: Bool) {
      let state = ongoing ? "ongoing" : "ended"
      let line = "HANG \(String(format: "%.2f", stall))s \(state) \(Date().formatted(.iso8601))\n"
      print(line, terminator: "")
      guard let handle = try? FileHandle(forWritingTo: log) else { return }
      handle.seekToEndOfFile()
      handle.write(Data(line.utf8))
      try? handle.close()
    }
  }
#endif
