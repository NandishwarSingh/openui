import XCTest

/// Sending a photo from the library through the composer. Needs the server
/// running live (the model has to look at the photo); the newest photo in the
/// simulator's library should be media/bangalore-palace.jpg (simctl addmedia).
@MainActor
final class PhotoFlowTests: XCTestCase {
  let app = XCUIApplication()

  override func setUp() async throws {
    continueAfterFailure = false
    XCUIDevice.shared.orientation = .portrait
  }

  func testAsksAboutAPhoto() throws {
    app.launchArguments = XCUIApplication.replayed
    app.launch()
    let add = app.buttons["Add photo"].firstMatch
    XCTAssertTrue(add.waitForExistence(timeout: 10))
    add.tap()
    // With a camera the + button is a menu; without one it opens the library.
    let library = app.buttons["Choose Photo"]
    if library.waitForExistence(timeout: 2) { library.tap() }
    let newest = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
    XCTAssertTrue(newest.waitForExistence(timeout: 10))
    // The picker runs out of process, so its cells aren't hittable; tap the spot.
    newest.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

    let field = app.textFields["Ask Planner"]
    XCTAssertTrue(field.waitForExistence(timeout: 10))
    field.tap()
    field.typeText("Where is this? Plan me a visit on Saturday.")
    shot("1-attached")
    app.buttons["Send"].tap()

    let answer = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'palace'")).firstMatch
    XCTAssertTrue(answer.waitForExistence(timeout: 90))
    sleep(12)
    shot("2-answer")
  }

  override func tearDown() async throws {
    XCTAssertEqual(app.state, .runningForeground, "the app is gone (crashed or killed)")
  }

  /// Saves a screenshot to $SHOTS (set TEST_RUNNER_SHOTS for xcodebuild).
  func shot(_ name: String) {
    guard let folder = ProcessInfo.processInfo.environment["SHOTS"] else { return }
    let data = XCUIScreen.main.screenshot().pngRepresentation
    try? data.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(name).png"))
  }
}
