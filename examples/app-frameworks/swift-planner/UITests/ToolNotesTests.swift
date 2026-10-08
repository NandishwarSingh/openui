import XCTest

/// Tool failures read as one plain note each (replayed answer that runs two
/// Apple Maps searches near the user).
@MainActor
final class ToolNotesTests: XCTestCase {
  let app = XCUIApplication()

  override func setUp() async throws {
    continueAfterFailure = false
  }

  func testLocationFailureNote() throws {
    app.launchArguments = XCUIApplication.replayed
    app.launch()
    let field = app.textFields["Ask Planner"]
    XCTAssertTrue(field.waitForExistence(timeout: 10))
    field.tap()
    field.typeText("palace test")
    app.buttons["Send"].tap()
    XCTAssertTrue(app.staticTexts["Bengaluru Palace"].waitForExistence(timeout: 30))
    let expectFailure = ProcessInfo.processInfo.environment["EXPECT_NO_LOCATION"] == "1"
    let note = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Searching Apple Maps:'"))
    if expectFailure {
      XCTAssertTrue(note.firstMatch.waitForExistence(timeout: 30))
      sleep(2)
      XCTAssertEqual(note.count, 1, "said once")
      XCTAssertFalse(note.firstMatch.label.contains("Domain"), note.firstMatch.label)
      XCTAssertTrue(note.firstMatch.label.contains("location"), note.firstMatch.label)
    } else {
      sleep(15)
      XCTAssertEqual(note.count, 0, "no failure with a location")
    }
    shot(expectFailure ? "notes-no-location" : "notes-located")
  }

  override func tearDown() async throws {
    XCTAssertEqual(app.state, .runningForeground, "the app is gone (crashed or killed)")
  }

  func shot(_ name: String) {
    guard let folder = ProcessInfo.processInfo.environment["SHOTS"] else { return }
    let data = XCUIScreen.main.screenshot().pngRepresentation
    try? data.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(name).png"))
  }
}
