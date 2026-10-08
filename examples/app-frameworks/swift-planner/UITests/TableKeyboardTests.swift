import XCTest

/// The editable table's keyboard keys, with a hardware keyboard (iPad).
@MainActor
final class TableKeyboardTests: XCTestCase {
  let app = XCUIApplication()

  override func setUp() async throws {
    continueAfterFailure = false
  }

  func testArrowsAndEnter() throws {
    app.launchArguments = XCUIApplication.replayed
    app.launch()
    let field = app.textFields["Ask Planner"]
    XCTAssertTrue(field.waitForExistence(timeout: 10))
    field.tap()
    field.typeText("table test")
    app.buttons["Send"].tap()

    let alex = app.textFields.matching(NSPredicate(format: "value == 'Alex'")).firstMatch
    XCTAssertTrue(alex.waitForExistence(timeout: 30))
    sleep(2)
    alex.tap()
    let focused = app.textFields.matching(NSPredicate(format: "hasKeyboardFocus == true")).firstMatch
    XCTAssertEqual(focused.value as? String, "Alex")

    app.typeKey(.downArrow, modifierFlags: [])
    expectFocus(on: "Jamie", focused, "Down moves to the next row")
    app.typeKey(.upArrow, modifierFlags: [])
    expectFocus(on: "Alex", focused, "Up moves back")

    // Enter keeps the edit and moves down.
    app.typeText("x\n")
    expectFocus(on: "Jamie", focused, "Enter moves down")
    XCTAssertTrue(app.textFields.matching(NSPredicate(format: "value == 'Alexx'")).firstMatch.exists)

    app.typeKey(.downArrow, modifierFlags: [])
    expectFocus(on: "Sam", focused, "Down again")
    shot("table")
  }

  /// Focus moves on the next frame, so give it a moment before checking.
  private func expectFocus(on value: String, _ focused: XCUIElement, _ message: String) {
    let moved = NSPredicate(format: "value == %@", value)
    let wait = XCTNSPredicateExpectation(predicate: moved, object: focused)
    XCTAssertEqual(XCTWaiter.wait(for: [wait], timeout: 2), .completed, message)
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
