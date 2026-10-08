import XCTest

/// Drives the app against the replay server, for the flows a person would
/// otherwise tap through by hand (and for recording them).
@MainActor
final class PaymentFlowTests: XCTestCase {
  let app = XCUIApplication()

  override func setUp() async throws {
    continueAfterFailure = false
    XCUIDevice.shared.orientation = .portrait
  }

  /// A streamed PayButton opens Razorpay's checkout (test mode), the demo
  /// bank approves the payment, the server verifies its signature, the button
  /// shows it as paid and the model hears about it.
  func testPaysWithRazorpayTestBank() throws {
    app.launchArguments = [
      "-prompt", "Book the jazz brunch for Saturday", "-paymentContact", "9999999999", "-clearPaymentUser", "YES",
    ] + XCUIApplication.replayed
    app.launch()
    let pay = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Book a table'")).firstMatch
    XCTAssertTrue(pay.waitForExistence(timeout: 20))
    shot("1-card")
    pay.tap()

    let netbanking = app.webViews.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Netbanking'"))
      .firstMatch
    XCTAssertTrue(netbanking.waitForExistence(timeout: 30))
    shot("2-methods")
    netbanking.tap()
    let bank = app.webViews.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Canara'")).firstMatch
    XCTAssertTrue(bank.waitForExistence(timeout: 10))
    bank.tap()
    app.webViews.buttons["Continue"].tap()

    let success = app.webViews.buttons["Success"]
    XCTAssertTrue(success.waitForExistence(timeout: 30))
    shot("3-bank")
    success.tap()

    XCTAssertTrue(app.staticTexts["Paid ₹499"].waitForExistence(timeout: 30))
    XCTAssertTrue(
      app.staticTexts["Paid ₹499 for Jazz brunch table for 2"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["You're booked"].waitForExistence(timeout: 20))
    shot("4-paid")
  }

  /// Checkout can close without reporting a payment the bank took (its pages
  /// were closed under it). The payment still counts: the app asks Razorpay,
  /// through the server, before treating it as cancelled.
  func testPaymentCountsWhenCheckoutLosesIt() throws {
    app.launchArguments = [
      "-prompt", "Book the jazz brunch for Saturday", "-paymentContact", "9999999999",
      "-clearPaymentUser", "YES", "-loseCheckoutResult", "YES",
    ] + XCUIApplication.replayed
    app.launch()
    let pay = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Book a table'")).firstMatch
    XCTAssertTrue(pay.waitForExistence(timeout: 20))
    pay.tap()
    let netbanking = app.webViews.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Netbanking'"))
      .firstMatch
    XCTAssertTrue(netbanking.waitForExistence(timeout: 30))
    netbanking.tap()
    let bank = app.webViews.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Canara'")).firstMatch
    XCTAssertTrue(bank.waitForExistence(timeout: 10))
    bank.tap()
    app.webViews.buttons["Continue"].tap()
    let success = app.webViews.buttons["Success"]
    XCTAssertTrue(success.waitForExistence(timeout: 30))
    shot("lost-1-bank")
    success.tap()
    XCTAssertTrue(app.staticTexts["Paid ₹499"].waitForExistence(timeout: 30), "the payment was lost")
    shot("lost-2-paid")
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
