import Foundation
import Observation

#if canImport(Razorpay)
  import Razorpay
  import RazorpayCore
  import UIKit
#endif

/// A payment the server has verified.
struct PaymentReceipt: Codable, Equatable, Sendable {
  var paymentId: String
  var orderId: String
  var amount: Int
  var currency: String

  var formattedAmount: String {
    (Double(amount) / 100).formatted(.currency(code: currency).precision(.fractionLength(0...2)))
  }
}

enum PaymentOutcome {
  case paid(PaymentReceipt)
  case dismissed
  case failed(String)
}

/// Razorpay checkout from start to finish: the server creates the order, the
/// user pays in Razorpay's checkout (the native SDK on iOS, the web checkout in
/// a sheet on macOS), and the server checks the signature before anything
/// counts as paid. Receipts are kept so a paid button stays paid.
@MainActor
@Observable
final class PaymentController {
  static let shared = PaymentController()

  /// The web checkout being shown (macOS).
  var webCheckout: WebCheckoutRequest?
  private(set) var receipts: [String: PaymentReceipt]

  private var server: PlannerServer { .shared }
  #if canImport(Razorpay)
    @ObservationIgnored private var native: NativeCheckout?
  #endif

  private init() {
    #if DEBUG && canImport(Razorpay)
      // `-clearPaymentUser YES` forgets the contact checkout remembers, for recordings.
      if UserDefaults.standard.bool(forKey: "clearPaymentUser") { RazorpayCheckout.clearUserData() }
    #endif
    receipts =
      UserDefaults.standard.data(forKey: "receipts")
      .flatMap { try? JSONDecoder().decode([String: PaymentReceipt].self, from: $0) } ?? [:]
  }

  /// Takes a payment of `amount` (in the smallest unit, e.g. paise) for the
  /// button identified by `key`.
  func pay(key: String, amount: Int, currency: String = "INR", description: String) async
    -> PaymentOutcome
  {
    do {
      let order = try await server.createOrder(
        amount: amount, currency: currency, receipt: "planner-\(UUID().uuidString.prefix(8))")
      var result = await checkout(order, description: description)
      #if DEBUG
        // `-loseCheckoutResult YES`: checkout's answer never arrives, as when
        // its pages close under it, to test that a payment still counts.
        if UserDefaults.standard.bool(forKey: "loseCheckoutResult") { result = .dismissed }
      #endif
      let paymentId: String
      switch result {
      case .paid(let id, let orderId, let signature):
        guard try await server.verifyPayment(orderId: orderId, paymentId: id, signature: signature)
        else { return .failed("The payment couldn't be verified.") }
        paymentId = id
      case .dismissed, .failed:
        // Checkout can report a cancel (or nothing useful) for a payment the
        // bank already took, so Razorpay has the last word on whether the
        // order was paid.
        guard let id = try? await server.paidPayment(orderId: order.orderId) else {
          if case .failed(let reason) = result { return .failed(reason) }
          return .dismissed
        }
        paymentId = id
      }
      let receipt = PaymentReceipt(
        paymentId: paymentId, orderId: order.orderId, amount: order.amount, currency: order.currency)
      receipts[key] = receipt
      UserDefaults.standard.set(try? JSONEncoder().encode(receipts), forKey: "receipts")
      return .paid(receipt)
    } catch {
      return .failed(error.localizedDescription)
    }
  }

  private func checkout(_ order: PlannerServer.Order, description: String) async -> CheckoutResult {
    #if canImport(Razorpay)
      let native = NativeCheckout()
      self.native = native
      defer { self.native = nil }
      return await native.open(order, description: description)
    #else
      return await withCheckedContinuation { continuation in
        webCheckout = WebCheckoutRequest(
          url: server.checkoutURL(order, description: description), continuation: continuation)
      }
    #endif
  }
}

enum CheckoutResult: Sendable {
  case paid(paymentId: String, orderId: String, signature: String)
  case dismissed
  case failed(String)
}

#if canImport(Razorpay)
  /// Razorpay's native checkout. It presents itself over the app and reports
  /// back through its delegate.
  @MainActor
  private final class NativeCheckout: NSObject {
    private var continuation: CheckedContinuation<CheckoutResult, Never>?
    /// Held while checkout is open, so it isn't released before it reports back.
    private var checkout: RazorpayCheckout?
    /// What checkout opens from. Checkout pushes its bank pages onto the
    /// navigation controller of the view controller it's given, and the app's
    /// is SwiftUI's: its title showed through, and SwiftUI pops pages it
    /// doesn't know about when the conversation redraws, which Razorpay
    /// reports as a cancel even after the bank took the payment.
    private var host: UIViewController?

    func open(_ order: PlannerServer.Order, description: String) async -> CheckoutResult {
      await withCheckedContinuation { continuation in
        self.continuation = continuation
        let checkout = RazorpayCheckout.initWithKey(order.keyId, andDelegateWithData: self)
        self.checkout = checkout
        var options: [AnyHashable: Any] = [
          "order_id": order.orderId, "amount": order.amount, "currency": order.currency,
          "name": "Planner", "description": description, "theme": ["color": "#5B6CF0"],
        ]
        // A known contact skips checkout's phone number step.
        if let contact = UserDefaults.standard.string(forKey: "paymentContact") {
          options["prefill"] = ["contact": contact]
        }
        guard let top = Self.topViewController() else { return checkout.open(options) }
        let host = UINavigationController(rootViewController: UIViewController())
        host.setNavigationBarHidden(true, animated: false)
        // Opaque: Razorpay's bank pages have a see-through bar, and the
        // conversation's title showed through it.
        host.viewControllers[0].view.backgroundColor = .systemBackground
        host.modalPresentationStyle = .fullScreen
        host.modalTransitionStyle = .crossDissolve
        self.host = host
        top.present(host, animated: true) {
          checkout.open(options, displayController: host.viewControllers[0])
        }
      }
    }

    private func finish(_ result: CheckoutResult) {
      continuation?.resume(returning: result)
      continuation = nil
      checkout = nil
      host?.dismiss(animated: true)
      host = nil
    }

    private static func topViewController() -> UIViewController? {
      let scene = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .first { $0.activationState == .foregroundActive }
      var controller = scene?.keyWindow?.rootViewController
      while let presented = controller?.presentedViewController { controller = presented }
      return controller
    }
  }

  extension NativeCheckout: @preconcurrency RazorpayPaymentCompletionProtocolWithData {
    func onPaymentSuccess(_ payment_id: String, andData response: [AnyHashable: Any]?) {
      finish(
        .paid(
          paymentId: payment_id, orderId: response?["razorpay_order_id"] as? String ?? "",
          signature: response?["razorpay_signature"] as? String ?? ""))
    }

    func onPaymentError(_ code: Int32, description str: String, andData response: [AnyHashable: Any]?) {
      // Code 2 is Razorpay's "payment cancelled by user".
      finish(code == 2 ? .dismissed : .failed(str))
    }
  }
#endif
