import XCTest

/// Paced walks through real answers, for recording the README and PR media
/// (`xcrun simctl io <device> recordVideo` while one runs; screenshots go to
/// $SHOTS). The answers are replayed, so they cost no model calls; the tools
/// behind them run for real. Set LANDSCAPE=1 to run on an iPad sideways.
@MainActor
final class MediaTests: XCTestCase {
  let app = XCUIApplication()

  override func setUp() async throws {
    continueAfterFailure = false
    let landscape = ProcessInfo.processInfo.environment["LANDSCAPE"] == "1"
    XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
  }

  /// Hourly temperatures and rain for three cities: tooltips, a hidden
  /// series, and the rain tab.
  func testCharts() throws {
    ask("Compare this Saturday temperatures and rain in Kathmandu, Pokhara and Delhi with charts")
    // Tabs follow the stream, so the last one is open when it ends.
    let temperatures = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Hourly'")).firstMatch
    XCTAssertTrue(temperatures.waitForExistence(timeout: 60))
    sleep(2)
    shot("charts-0")
    bringIntoView(temperatures)
    temperatures.tap()
    let noon = app.otherElements["12:00"].firstMatch
    XCTAssertTrue(noon.waitForExistence(timeout: 10))
    bringIntoView(noon)
    sleep(1)
    noon.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    sleep(2)
    shot("charts-1-tooltip")
    app.otherElements["16:00"].firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
      .tap()
    sleep(2)
    let delhi = app.buttons["Delhi"].firstMatch
    if delhi.exists {
      delhi.tap()
      sleep(2)
      shot("charts-2-hidden")
      delhi.tap()
      sleep(1)
    }
    let rain = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Rain'")).firstMatch
    if rain.exists {
      rain.tap()
      sleep(2)
      app.otherElements["14:00"].firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        .tap()
      sleep(2)
      shot("charts-3-rain")
    }
    let table = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Table'")).firstMatch
    if table.exists {
      table.tap()
      sleep(2)
      shot("charts-4-table")
    }
  }

  /// Sights in Rome as photo cards, then the map full screen.
  func testRome() throws {
    ask("Show me the most beautiful sights in Rome with lots of photos")
    let map = mapElement
    XCTAssertTrue(map.waitForExistence(timeout: 60))
    sleep(4)
    shot("rome-0")
    for step in 1...3 {
      scroll(by: -280)
      shot("rome-\(step)")
    }
    bringIntoView(map)
    map.tap()
    XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
    sleep(3)
    shot("rome-map")
    app.buttons["Done"].tap()
    sleep(1)
  }

  /// The trip's food photos: the mosaic, then the viewer, swiped through.
  func testGallery() throws {
    ask("Plan me a trip to Kathmandu")
    XCTAssertTrue(mapElement.waitForExistence(timeout: 60))
    let header = app.staticTexts["Local Cuisine"].firstMatch
    XCTAssertTrue(header.waitForExistence(timeout: 10))
    for _ in 0..<10 where header.frame.minY > app.windows.firstMatch.frame.height * 0.35 {
      scroll(by: -220)
    }
    sleep(3)
    shot("gallery-0")
    app.coordinate(withNormalizedOffset: .zero)
      .withOffset(CGVector(dx: header.frame.minX + 70, dy: header.frame.maxY + 110)).tap()
    XCTAssertTrue(app.staticTexts["All Photos"].waitForExistence(timeout: 5))
    sleep(2)
    shot("gallery-1-viewer")
    for _ in 0..<3 {
      app.scrollViews.firstMatch.swipeLeft()
      sleep(2)
    }
    shot("gallery-2-swiped")
    app.buttons["Close gallery"].tap()
    sleep(1)
  }

  /// Booking a real café from Apple Maps: Razorpay's checkout in test mode,
  /// its test bank, then the model confirming the paid deposit.
  func testBooking() throws {
    app.launchArguments = XCUIApplication.replayed.filter { $0 != "-replayOnly" && $0 != "YES" } + [
      "-paymentContact", "9999999999", "-clearPaymentUser", "YES",
    ]
    launchAndAsk("Find a nice cafe in Indiranagar for Saturday brunch and let me pay a deposit here")
    let pay = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Deposit'")).firstMatch
    XCTAssertTrue(pay.waitForExistence(timeout: 60))
    sleep(4)
    shot("booking-0")
    bringIntoView(pay)
    sleep(1)
    shot("booking-1")
    pay.tap()
    let netbanking = app.webViews.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Netbanking'"))
      .firstMatch
    XCTAssertTrue(netbanking.waitForExistence(timeout: 30))
    sleep(1)
    shot("booking-2-checkout")
    netbanking.tap()
    let bank = app.webViews.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Canara'")).firstMatch
    XCTAssertTrue(bank.waitForExistence(timeout: 10))
    bank.tap()
    app.webViews.buttons["Continue"].tap()
    let success = app.webViews.buttons["Success"]
    XCTAssertTrue(success.waitForExistence(timeout: 30))
    sleep(1)
    shot("booking-3-bank")
    success.tap()
    XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Paid ₹500'")).firstMatch
      .waitForExistence(timeout: 30))
    // The confirmation comes from the model.
    sleep(3)
    XCTAssertTrue(app.buttons["Stop"].waitForNonExistence(timeout: 90))
    sleep(4)
    shot("booking-4-paid")
  }

  // MARK: Helpers

  private var mapElement: XCUIElement {
    app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Map of'")).firstMatch
  }

  private func ask(_ prompt: String) {
    app.launchArguments = XCUIApplication.replayed
    launchAndAsk(prompt)
  }

  private func launchAndAsk(_ prompt: String) {
    app.launch()
    sleep(1)
    let field = app.textFields["Ask Planner"]
    XCTAssertTrue(field.waitForExistence(timeout: 10))
    field.tap()
    field.typeText(prompt)
    sleep(1)
    app.buttons["Send"].tap()
    XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["Stop"].waitForNonExistence(timeout: 120))
  }

  /// The transcript: the outermost scroll view (an iPad's sidebar is a list).
  private var transcript: XCUIElement { app.scrollViews.firstMatch }

  private func scroll(by distance: CGFloat) {
    let start = transcript.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
    start.press(
      forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: distance)),
      withVelocity: .slow, thenHoldForDuration: 0.6)
    sleep(2)
  }

  private func bringIntoView(_ element: XCUIElement) {
    let visible = transcript.frame.insetBy(dx: 0, dy: 90)
    for _ in 0..<8 where !visible.contains(element.frame) {
      let step = max(-260, min(260, element.frame.midY - visible.midY))
      scroll(by: -step)
    }
  }

  private func shot(_ name: String) {
    guard let folder = ProcessInfo.processInfo.environment["SHOTS"] else { return }
    try? XCUIScreen.main.screenshot().pngRepresentation.write(
      to: URL(fileURLWithPath: folder).appendingPathComponent("\(name).png"))
  }
}
