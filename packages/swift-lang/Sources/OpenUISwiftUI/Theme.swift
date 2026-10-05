import SwiftUI

/// Spacing, shapes and colors the built-in components use. Override parts of
/// it with `.environment(\.openUITheme, theme)`.
public struct OpenUITheme: Sendable {
  public var spacing: CGFloat = 12
  public var compactSpacing: CGFloat = 6
  public var cornerRadius: CGFloat = 10
  public var smallCornerRadius: CGFloat = 6
  public var cardPadding: CGFloat = 16
  public var accent: Color = .accentColor
  public var surface: Color = .platformSecondaryBackground
  public var sunkSurface: Color = .platformTertiaryBackground
  public var border: Color = .secondary.opacity(0.25)
  public var chartHeight: CGFloat = 220

  public init() {}

  public static let `default` = OpenUITheme()
}

private struct ThemeKey: EnvironmentKey {
  static let defaultValue = OpenUITheme.default
}

extension EnvironmentValues {
  public var openUITheme: OpenUITheme {
    get { self[ThemeKey.self] }
    set { self[ThemeKey.self] = newValue }
  }
}

extension Color {
  static var platformSecondaryBackground: Color {
    #if os(macOS)
      Color(nsColor: .controlBackgroundColor)
    #else
      Color(uiColor: .secondarySystemBackground)
    #endif
  }

  /// A light recessed fill that works in light and dark mode on every platform.
  static var platformTertiaryBackground: Color { Color.primary.opacity(0.06) }
}

/// Status colors shared by callouts, tags and form errors.
func statusColor(_ variant: String?) -> Color {
  switch variant {
  case "info": return .blue
  case "warning": return .orange
  case "error", "danger": return .red
  case "success": return .green
  default: return .secondary
  }
}

/// The surface behind a "card" / "sunk" / "clear" container variant.
struct SurfaceModifier: ViewModifier {
  let variant: String
  @Environment(\.openUITheme) private var theme

  func body(content: Content) -> some View {
    switch variant {
    case "clear":
      content
    case "sunk":
      content.padding(theme.cardPadding)
        .background(theme.sunkSurface, in: RoundedRectangle(cornerRadius: theme.cornerRadius))
    default:
      content.padding(theme.cardPadding)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: theme.cornerRadius).strokeBorder(theme.border))
    }
  }
}

extension View {
  func surface(_ variant: String) -> some View { modifier(SurfaceModifier(variant: variant)) }
}
