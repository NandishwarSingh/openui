import SwiftUI
import WebKit

/// Razorpay's web checkout, served by the Planner server. The page reports the
/// result by navigating to `planner-payment://result?…`, which the web view
/// intercepts instead of loading.
struct WebCheckoutRequest: Identifiable {
  let id = UUID()
  let url: URL
  let continuation: CheckedContinuation<CheckoutResult, Never>
}

struct WebCheckoutSheet: View {
  let request: WebCheckoutRequest
  @Environment(\.dismiss) private var dismiss
  @State private var finished = false

  var body: some View {
    CheckoutWebView(url: request.url) { result in finish(result) }
      .frame(minWidth: 460, minHeight: 640)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { finish(.dismissed) }
        }
      }
      .onDisappear { finish(.dismissed) }
  }

  private func finish(_ result: CheckoutResult) {
    guard !finished else { return }
    finished = true
    request.continuation.resume(returning: result)
    dismiss()
  }
}

@MainActor
private struct CheckoutWebView {
  let url: URL
  let onResult: @MainActor (CheckoutResult) -> Void

  func makeCoordinator() -> Coordinator { Coordinator(onResult: onResult) }

  func makeWebView(context: Context) -> WKWebView {
    let webView = WKWebView()
    webView.navigationDelegate = context.coordinator
    webView.uiDelegate = context.coordinator
    webView.load(URLRequest(url: url))
    return webView
  }

  @MainActor
  final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
    let onResult: @MainActor (CheckoutResult) -> Void
    init(onResult: @escaping @MainActor (CheckoutResult) -> Void) { self.onResult = onResult }

    func webView(
      _ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
      decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
      guard let url = action.request.url, url.scheme == "planner-payment" else {
        return decisionHandler(.allow)
      }
      decisionHandler(.cancel)
      let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
      let value = { (name: String) in query.first { $0.name == name }?.value ?? "" }
      switch value("status") {
      case "paid":
        onResult(.paid(paymentId: value("paymentId"), orderId: value("orderId"), signature: value("signature")))
      case "failed": onResult(.failed(value("reason")))
      default: onResult(.dismissed)
      }
    }

    /// Bank pages that open in a new window load in the same view instead.
    func webView(
      _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
      for action: WKNavigationAction, windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
      webView.load(action.request)
      return nil
    }
  }
}

#if os(macOS)
  extension CheckoutWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView { makeWebView(context: context) }
    func updateNSView(_ view: WKWebView, context: Context) {}
  }
#else
  extension CheckoutWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView { makeWebView(context: context) }
    func updateUIView(_ view: WKWebView, context: Context) {}
  }
#endif
