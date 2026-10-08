import XCTest

/// Dragging a range slider's thumb moves it with the finger: a drag of a
/// third of the track moves the value by a third of the range, not further.
@MainActor
final class SliderFlowTests: XCTestCase {
  let app = XCUIApplication()

  override func setUp() async throws {
    continueAfterFailure = false
    XCUIDevice.shared.orientation = .portrait
  }

  func testRangeThumbFollowsTheDrag() throws {
    app.launchArguments = XCUIApplication.replayed + ["-prompt", "slider test"]
    app.launch()
    let lower = app.descendants(matching: .any)["Minimum"]
    let upper = app.descendants(matching: .any)["Maximum"]
    XCTAssertTrue(lower.waitForExistence(timeout: 30))
    sleep(1)
    XCTAssertEqual(lower.value as? String, "20")
    XCTAssertEqual(upper.value as? String, "80")
    // The thumbs are 60% of the track apart, so half that distance is 30%:
    // from 20 to 50.
    let distance = upper.frame.midX - lower.frame.midX
    let start = lower.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    start.press(
      forDuration: 0.2, thenDragTo: start.withOffset(CGVector(dx: distance / 2, dy: 0)),
      withVelocity: .slow, thenHoldForDuration: 0.3)
    let value = Double(lower.value as? String ?? "") ?? -1
    XCTAssertEqual(value, 50, accuracy: 2, "the thumb ended at \(value)")
    XCTAssertEqual(upper.value as? String, "80", "the other thumb stays")
  }
}
