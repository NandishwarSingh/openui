import XCTest

/// Chart tooltips and legends with real taps (replayed answer, no model call).
@MainActor
final class ChartFlowTests: XCTestCase {
  let app = XCUIApplication()

  override func setUp() async throws {
    continueAfterFailure = false
  }

  func testTooltipAndLegend() throws {
    app.launchArguments = XCUIApplication.replayed
    app.launch()
    let field = app.textFields["Ask Planner"]
    XCTAssertTrue(field.waitForExistence(timeout: 10))
    field.tap()
    field.typeText("chart test")
    app.buttons["Send"].tap()

    // Swift Charts exposes each category as an element spanning its bars.
    let wednesday = app.otherElements["Wed"].firstMatch
    XCTAssertTrue(wednesday.waitForExistence(timeout: 30))
    sleep(3)
    wednesday.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    let value = app.staticTexts["1,620"]
    XCTAssertTrue(value.waitForExistence(timeout: 5), "tooltip shows Wednesday's coffee")
    XCTAssertTrue(app.staticTexts["540"].exists, "and the other series")
    shot("1-tooltip")

    // The same category again closes it.
    wednesday.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    XCTAssertTrue(value.waitForNonExistence(timeout: 5))

    // Hide Tea from the legend, then the tooltip leaves it out.
    let tea = app.buttons["Tea"].firstMatch
    XCTAssertTrue(tea.exists)
    tea.tap()
    XCTAssertEqual(tea.value as? String, "Hidden")
    wednesday.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    XCTAssertTrue(app.staticTexts["1,620"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.staticTexts["540"].exists, "hidden series left out")
    shot("2-hidden")

    // Hiding the other two leaves one visible: the last one can't be hidden.
    app.buttons["Coffee"].firstMatch.tap()
    app.buttons["Juice"].firstMatch.tap()
    XCTAssertEqual(app.buttons["Juice"].firstMatch.value as? String, "Shown")
    tea.tap()
    XCTAssertEqual(tea.value as? String, "Shown")
    shot("3-legend")

    // Pie: slices are sorted largest first, so Rent starts at 12 o'clock.
    let rent = app.otherElements["Rent"].firstMatch
    XCTAssertTrue(rent.waitForExistence(timeout: 5))
    bringIntoView(rent)
    // It's a donut: the middle of the slice's frame is in the hole, so tap
    // out on the ring.
    rent.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.3)).tap()
    XCTAssertTrue(app.staticTexts["Rent"].waitForExistence(timeout: 5))
    shot("4-pie")

    // Stacked bar: value and share of the tapped segment.
    let todo = app.otherElements["To do"].firstMatch
    bringIntoView(todo)
    todo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    XCTAssertTrue(app.staticTexts["Percentage"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["32.1%"].exists)
    XCTAssertFalse(app.staticTexts["1,200"].exists, "opening a tooltip closes the pie's")
    shot("5-stacked")
  }

  /// Scrolls the transcript (not the iPad sidebar's list) until `element` is
  /// well inside it: drags by the distance and holds before letting go, so
  /// there's no momentum to overshoot in a small window.
  func bringIntoView(_ element: XCUIElement) {
    let transcript = app.scrollViews.containing(.other, identifier: element.label).firstMatch
    let visible = transcript.frame.insetBy(dx: 0, dy: 80)
    for _ in 0..<6 where !visible.contains(element.frame) {
      let step = max(-200, min(200, element.frame.midY - visible.midY))
      let center = transcript.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
      center.press(
        forDuration: 0.05, thenDragTo: center.withOffset(CGVector(dx: 0, dy: -step)),
        withVelocity: .slow, thenHoldForDuration: 0.5)
    }
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
