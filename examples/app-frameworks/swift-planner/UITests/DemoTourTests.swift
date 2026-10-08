import XCTest

/// Pages through the demo's main answers (replayed) and screenshots each
/// screenful, for reviewing the demo as someone watching it would see it.
@MainActor
final class DemoTourTests: XCTestCase {
  let app = XCUIApplication()

  override func setUp() async throws {
    continueAfterFailure = true
  }

  func testSaturday() throws { tour("What does my Saturday look like?", "saturday") }
  func testJazzBrunch() throws { tour("Book me a jazz brunch", "brunch") }
  func testWorthSeeing() throws { tour("What's worth seeing near me?", "seeing") }
  func testPalace() throws { tour("palace test", "palace") }

  /// The inline map is a preview: tapping opens it full screen.
  func testMapOpensFullScreen() throws {
    tour("What's worth seeing near me?", "map", pages: 1)
    let map = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Map of'"))
      .firstMatch
    XCTAssertTrue(map.waitForExistence(timeout: 10))
    let transcript = app.scrollViews.firstMatch
    for _ in 0..<6 where !transcript.frame.insetBy(dx: 0, dy: 100).contains(map.frame) {
      let center = transcript.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
      center.press(
        forDuration: 0.05, thenDragTo: center.withOffset(CGVector(dx: 0, dy: -200)),
        withVelocity: .slow, thenHoldForDuration: 0.4)
    }
    map.tap()
    XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
    sleep(2)
    save(XCUIScreen.main.screenshot().pngRepresentation, "map-expanded")
    app.buttons["Done"].tap()
    XCTAssertTrue(app.buttons["Done"].waitForNonExistence(timeout: 5))
  }

  private func tour(_ prompt: String, _ name: String, pages: Int = 10) {
    app.launchArguments = XCUIApplication.replayed
    app.launch()
    let field = app.textFields["Ask Planner"]
    XCTAssertTrue(field.waitForExistence(timeout: 10))
    field.tap()
    field.typeText(prompt)
    app.buttons["Send"].tap()
    XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["Stop"].waitForNonExistence(timeout: 120), "still streaming")
    // Queries and photos settle.
    sleep(8)
    let transcript = app.scrollViews.firstMatch
    // Back to the top of the answer.
    for _ in 0..<6 { transcript.swipeDown(velocity: .fast) }
    sleep(1)
    var previous = Data()
    for page in 0..<pages {
      let image = XCUIScreen.main.screenshot().pngRepresentation
      if image == previous { break }
      save(image, "\(name)-\(page)")
      previous = image
      let center = transcript.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
      center.press(
        forDuration: 0.05, thenDragTo: center.withOffset(CGVector(dx: 0, dy: -420)),
        withVelocity: .slow, thenHoldForDuration: 0.4)
      sleep(1)
    }
  }

  func save(_ data: Data, _ name: String) {
    guard let folder = ProcessInfo.processInfo.environment["SHOTS"] else { return }
    try? data.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(name).png"))
  }
}
