import XCTest

/// The image gallery: mosaic, viewer, paging and thumbnails, with real taps
/// (replayed answer, no model call).
@MainActor
final class GalleryFlowTests: XCTestCase {
  let app = XCUIApplication()

  override func setUp() async throws {
    continueAfterFailure = false
  }

  func testGalleryViewer() throws {
    app.launchArguments = XCUIApplication.replayed
    app.launch()
    let field = app.textFields["Ask Planner"]
    XCTAssertTrue(field.waitForExistence(timeout: 10))
    field.tap()
    field.typeText("gallery test")
    app.buttons["Send"].tap()

    let first = app.buttons["Photo 1"]
    XCTAssertTrue(first.waitForExistence(timeout: 30))
    XCTAssertFalse(app.buttons["Photo 6"].exists, "only five images in the mosaic")
    sleep(4)
    shot("1-mosaic")

    first.tap()
    XCTAssertTrue(app.staticTexts["All Photos"].waitForExistence(timeout: 5))
    sleep(3)
    shot("2-viewer")

    // Swipe to the next image: its thumbnail becomes the selected one.
    app.scrollViews.firstMatch.swipeLeft()
    let second = app.buttons.matching(NSPredicate(format: "label == 'Photo 2' AND selected == true"))
    XCTAssertTrue(second.firstMatch.waitForExistence(timeout: 5))
    sleep(2)
    shot("3-swiped")

    // A thumbnail past the mosaic.
    let seventh = app.buttons["Photo 7"]
    let screen = app.windows.firstMatch.frame
    for _ in 0..<4 where !screen.contains(seventh.frame) {
      app.scrollViews.element(boundBy: 1).swipeLeft()
    }
    seventh.tap()
    let selected = app.buttons.matching(NSPredicate(format: "label == 'Photo 7' AND selected == true"))
    XCTAssertTrue(selected.firstMatch.waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Picture 7 of 7"].waitForExistence(timeout: 5))
    sleep(2)
    shot("4-thumbnail")

    app.buttons["Close gallery"].tap()
    XCTAssertTrue(app.staticTexts["All Photos"].waitForNonExistence(timeout: 5))

    // Show All opens on the last image looked at.
    app.buttons["Show All"].tap()
    XCTAssertTrue(app.staticTexts["Picture 7 of 7"].waitForExistence(timeout: 5))
    shot("5-show-all")
    app.buttons["Close gallery"].tap()
    XCTAssertTrue(app.staticTexts["All Photos"].waitForNonExistence(timeout: 5))
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
