import Observation
import SwiftUI

/// Tools that are running right now, for the status chips under a response
/// ("Checking your calendar…").
@MainActor
@Observable
final class ToolActivity {
  static let shared = ToolActivity()
  private(set) var running: [String] = []

  func begin(_ label: String) { running.append(label) }

  func end(_ label: String) {
    if let index = running.firstIndex(of: label) { running.remove(at: index) }
  }
}

/// Shown on a response while its queries load: what's running, e.g.
/// "Checking your calendar".
struct ToolStatusChip: View {
  private var activity = ToolActivity.shared

  var body: some View {
    HStack(spacing: 6) {
      ProgressView().controlSize(.mini).tint(Pastel.butter.onSolid)
      Text(activity.running.last ?? "Loading")
        .contentTransition(.opacity)
    }
    .font(.caption.weight(.semibold))
    .foregroundStyle(Pastel.butter.onSolid)
    .padding(.horizontal, 10)
    .padding(.vertical, 5)
    .background(Pastel.butter.chip, in: Capsule())
    .overlay(Capsule().strokeBorder(Pastel.card, lineWidth: 2))
    // The renderer puts this in its top trailing corner; lift it onto the
    // card's top edge so it doesn't cover the response's title.
    .offset(y: -37)
    .animation(.easeOut(duration: 0.2), value: activity.running.last)
    .transition(.opacity)
  }
}
