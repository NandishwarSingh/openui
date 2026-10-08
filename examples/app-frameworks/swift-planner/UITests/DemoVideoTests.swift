import XCTest

/// A paced walk through one answer, for recording the demo video
/// (`xcrun simctl io <device> recordVideo` while it runs). Replayed, so it
/// costs no model calls; the tools behind it run for real.
@MainActor
final class DemoVideoTests: XCTestCase {
  let app = XCUIApplication()

  override func setUp() async throws {
    continueAfterFailure = false
    XCUIDevice.shared.orientation = .portrait
  }

  func testTripToKathmandu() throws {
    app.launchArguments = XCUIApplication.replayed
    app.launch()
    sleep(2)
    let field = app.textFields["Ask Planner"]
    XCTAssertTrue(field.waitForExistence(timeout: 10))
    field.tap()
    field.typeText("Plan me a trip to Kathmandu")
    sleep(1)
    app.buttons["Send"].tap()
    XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["Stop"].waitForNonExistence(timeout: 120))
    let map = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Map of'"))
      .firstMatch
    XCTAssertTrue(map.waitForExistence(timeout: 60))
    sleep(3)
    let transcript = app.scrollViews.firstMatch
    // Down at reading pace until the whole map is on screen, then open it.
    for _ in 0..<8 where !transcript.frame.insetBy(dx: 0, dy: 60).contains(map.frame) {
      scroll(transcript, by: -260)
    }
    map.tap()
    XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
    sleep(3)
    app.buttons["Done"].tap()
    sleep(1)
    for _ in 0..<6 { scroll(transcript, by: -320) }
    sleep(2)
  }

  private func scroll(_ view: XCUIElement, by distance: CGFloat) {
    let start = view.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
    start.press(
      forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: distance)),
      withVelocity: .slow, thenHoldForDuration: 0.6)
    sleep(2)
  }
}
