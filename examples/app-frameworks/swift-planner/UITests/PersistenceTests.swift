import XCTest

/// A reopened conversation shows the places and photos it showed before
/// without calling the tools again: the second step reopens it with every
/// tool failing as if offline. Run the steps in order.
@MainActor
final class PersistenceTests: XCTestCase {
  let app = XCUIApplication()
  private let prompt = "Show me what is worth seeing near me"

  override func setUp() async throws {
    continueAfterFailure = false
    XCUIDevice.shared.orientation = .portrait
  }

  func test1AnswerWithPlaces() throws {
    app.launchArguments = XCUIApplication.replayed + ["-prompt", prompt]
    app.launch()
    XCTAssertTrue(map.waitForExistence(timeout: 60), "no places on the map")
    // Saves are batched; give the last one time to land.
    sleep(2)
  }

  func test2ReopenedWithoutTools() throws {
    app.launchArguments = XCUIApplication.replayed + ["-offline", "YES"]
    app.launch()
    // The app opens a new plan; the saved one is in the list behind it.
    let back = app.navigationBars.buttons.firstMatch
    XCTAssertTrue(back.waitForExistence(timeout: 10))
    back.tap()
    let saved = app.staticTexts[prompt].firstMatch
    XCTAssertTrue(saved.waitForExistence(timeout: 10))
    saved.tap()
    XCTAssertTrue(map.waitForExistence(timeout: 5), "the places didn't come back")
    let notes = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'offline'"))
    XCTAssertEqual(notes.count, 0, "a tool ran again and failed: \(notes.firstMatch.label)")
    if let folder = ProcessInfo.processInfo.environment["SHOTS"] {
      let data = XCUIScreen.main.screenshot().pngRepresentation
      try? data.write(to: URL(fileURLWithPath: folder).appendingPathComponent("reopened.png"))
    }
  }

  private var map: XCUIElement {
    app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Map of'")).firstMatch
  }
}
