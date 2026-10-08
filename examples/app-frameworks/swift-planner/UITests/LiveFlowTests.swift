import XCTest

/// Real conversations with the live model, for the turns that only break with
/// a real model behind them: follow-ups, photos on a later turn, plain-text
/// answers, payments and calendar writes. Each test makes one to three model
/// calls, so run them on purpose:
/// `-only-testing:PlannerUITests/LiveFlowTests`.
@MainActor
final class LiveFlowTests: XCTestCase {
  let app = XCUIApplication()

  override func setUp() async throws {
    continueAfterFailure = false
    XCUIDevice.shared.orientation = .portrait
  }

  /// Tapping a follow-up sends it in Cloud's content/context form.
  func testFollowUpTurn() throws {
    start("What is the forecast where I am this Saturday? End with exactly one follow-up suggestion: Show the hourly forecast")
    let followUp = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'hourly forecast'")).firstMatch
    XCTAssertTrue(followUp.waitForExistence(timeout: 10), "no follow-up to tap")
    followUp.tap()
    waitForAnswer("2-follow-up")
  }

  /// The bug from a real session: a photo sent without text on a later turn.
  func testPhotoWithoutTextOnLaterTurn() throws {
    start("I will send you a photo of a place. Reply in one short sentence for now.")
    let add = app.buttons["Add photo"].firstMatch
    add.tap()
    let library = app.buttons["Choose Photo"]
    if library.waitForExistence(timeout: 2) { library.tap() }
    let newest = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
    XCTAssertTrue(newest.waitForExistence(timeout: 10))
    newest.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    let send = app.buttons["Send"]
    XCTAssertTrue(send.waitForExistence(timeout: 10))
    sleep(1)
    send.tap()
    waitForAnswer("2-photo")
  }

  /// A typed second turn. Sending dismisses the keyboard; with a heavy answer
  /// (the recording for this prompt) that once froze the app, because the
  /// answer was resized on every frame of the keyboard animating away.
  func testTextOnLaterTurn() throws {
    start("I am about to tell you about a place. Reply in one short sentence for now.")
    let field = app.textFields["Ask Planner"]
    field.tap()
    field.typeText("It is the big palace in the middle of Bengaluru")
    app.buttons["Send"].tap()
    waitForAnswer("2-text")
  }

  /// A trip somewhere else: the sights, photos and map are of that place,
  /// not of where the user is. Pages through the answer for a look.
  func testTripElsewhere() throws {
    start("Plan me a trip to Kathmandu")
    let map = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Map of'"))
      .firstMatch
    XCTAssertTrue(map.waitForExistence(timeout: 20), "no places on the map")
    let transcript = app.scrollViews.firstMatch
    for _ in 0..<6 { transcript.swipeDown(velocity: .fast) }
    for page in 0..<8 {
      shot("trip-\(page)")
      let center = transcript.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
      center.press(
        forDuration: 0.05, thenDragTo: center.withOffset(CGVector(dx: 0, dy: -420)),
        withVelocity: .slow, thenHoldForDuration: 0.4)
      sleep(1)
    }
  }

  /// A conversational reply with no UI must still show up.
  func testPlainTextReply() throws {
    start("Reply with one short plain-text sentence and no components: say hello.")
  }

  /// The turn after a payment: the payment report is a content/context message.
  func testTurnAfterPayment() throws {
    // The replay server answers the first turn from a recording and sends the
    // one after the payment to the model.
    app.launchArguments = [
      "-prompt", "Book it, live after paying", "-paymentContact", "9999999999",
      "-clearPaymentUser", "YES", "-serverAddress", "http://localhost:8788",
    ]
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
    success.tap()
    XCTAssertTrue(app.staticTexts["Paid ₹499"].waitForExistence(timeout: 30))
    waitForAnswer("2-after-payment")
  }

  /// A Mutation run by a button: the event is written, then confirmed.
  func testCalendarWrite() throws {
    start("Suggest a 30 minute coffee break at 16:00 this Saturday with a button labelled Add coffee break that adds it to my calendar.")
    let add = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'coffee break'")).firstMatch
    XCTAssertTrue(add.waitForExistence(timeout: 10), "no button to add the event")
    add.tap()
    waitForAnswer("2-calendar")
  }

  // MARK: Helpers

  /// Launches with a first message and waits for its answer.
  private func start(_ prompt: String) {
    app.launchArguments = ["-prompt", prompt]
    // REPLAY_ONLY=1 (TEST_RUNNER_REPLAY_ONLY for xcodebuild) runs these
    // against recordings only, without spending model calls.
    if ProcessInfo.processInfo.environment["REPLAY_ONLY"] != nil {
      app.launchArguments += XCUIApplication.replayed
    }
    app.launch()
    waitForAnswer("1-first")
  }

  /// Waits for the answer in progress to finish, then checks it isn't a failure.
  private func waitForAnswer(_ name: String) {
    sleep(2)
    let stop = app.buttons["Stop"]
    let deadline = Date().addingTimeInterval(120)
    while stop.exists, Date() < deadline { sleep(1) }
    sleep(4)  // Queries load once the stream ends.
    shot("\(name)")
    XCTAssertEqual(app.state, .runningForeground, "\(name): the app is gone (crashed or killed)")
    XCTAssertFalse(app.buttons["Retry"].exists, "\(name): the answer failed")
    XCTAssertFalse(
      app.staticTexts["That answer didn't come out right. Try asking again."].exists,
      "\(name): the answer had nothing to show")
  }

  /// Saves a screenshot to $SHOTS (set TEST_RUNNER_SHOTS for xcodebuild).
  private func shot(_ name: String) {
    guard let folder = ProcessInfo.processInfo.environment["SHOTS"] else { return }
    let data = XCUIScreen.main.screenshot().pngRepresentation
    try? data.write(
      to: URL(fileURLWithPath: folder).appendingPathComponent("\(name)-\(self.name.split(separator: " ").last ?? "").png"))
  }
}
