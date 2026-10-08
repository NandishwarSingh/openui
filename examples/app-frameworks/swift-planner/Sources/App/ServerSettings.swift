import SwiftUI

/// Whether the Planner server answers, checked at launch and from Settings.
@MainActor
@Observable
final class ServerStatus {
  static let shared = ServerStatus()

  enum State: Equatable {
    case unknown, checking
    case reachable(chat: Bool, payments: Bool)
    case unreachable
  }

  private(set) var state = State.unknown
  /// Whether the server takes payments with Razorpay test keys.
  private(set) var paymentsTestMode = false
  var showingSettings = false

  func check() async {
    state = .checking
    do {
      let health = try await PlannerServer.shared.health()
      paymentsTestMode = health.paymentsTestMode ?? false
      state = .reachable(chat: health.chat, payments: health.payments)
    } catch {
      state = .unreachable
    }
  }
}

/// Where the Planner server runs. The simulator and the Mac use localhost; a
/// phone needs the Mac's address on the same Wi-Fi, which the server prints
/// when it starts.
struct ServerSettingsView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var address = PlannerServer.shared.baseURL.absoluteString
  private var status = ServerStatus.shared

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("http://your-mac.local:8787", text: $address)
            .textContentType(.URL)
            .autocorrectionDisabled()
            #if os(iOS)
              .keyboardType(.URL)
              .textInputAutocapitalization(.never)
            #endif
          Button("Check connection") { Task { await apply() } }
        } header: {
          Text("Planner server")
        } footer: {
          Text(
            "Run `node server.mjs` on your Mac. On a phone, use the address it prints, your Mac's name ending in .local, not localhost."
          )
        }
        Section("Status") { statusRow }
      }
      .formStyle(.grouped)
      .navigationTitle("Settings")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") {
            Task {
              await apply()
              dismiss()
            }
          }
        }
      }
    }
    .frame(minWidth: 380, minHeight: 320)
  }

  @ViewBuilder
  private var statusRow: some View {
    switch status.state {
    case .unknown:
      Text("Not checked yet").foregroundStyle(.secondary)
    case .checking:
      HStack(spacing: 8) {
        ProgressView().controlSize(.small)
        Text("Checking…")
      }
    case .reachable(let chat, let payments):
      VStack(alignment: .leading, spacing: 4) {
        Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(Pastel.mint.ink)
        Text(chat ? "Chat is ready." : "Chat needs THESYS_API_KEY in server/.env.")
        Text(
          !payments
            ? "Payments need the Razorpay keys in server/.env."
            : status.paymentsTestMode ? "Payments are ready, in Razorpay's test mode." : "Payments are ready.")
      }
      .font(.subheadline)
    case .unreachable:
      Label("Can't reach the server at this address.", systemImage: "wifi.exclamationmark")
        .foregroundStyle(Pastel.peach.ink)
    }
  }

  private func apply() async {
    let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
    let url = URL(string: trimmed.contains("://") ? trimmed : "http://\(trimmed)")
    PlannerServer.address = url == PlannerServer.defaultAddress ? nil : url
    await status.check()
  }
}
