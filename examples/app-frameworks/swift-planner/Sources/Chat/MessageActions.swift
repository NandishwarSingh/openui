import Foundation
import SwiftUI

/// What native components inside a response can do in the conversation: send
/// a photo or report a payment as the user's next message. Each message row
/// provides its own.
struct MessageActions: Sendable {
  var messageID: UUID?
  var sendPhoto: @MainActor @Sendable (_ jpeg: Data, _ message: String) -> Void = { _, _ in }
  var reportPayment: @MainActor @Sendable (_ receipt: PaymentReceipt, _ description: String) -> Void = {
    _, _ in
  }
}

extension EnvironmentValues {
  @Entry var messageActions = MessageActions()
}
