import OpenUISwiftUI
import SwiftUI

/// Planner's pastel palette. Each tone has:
/// - `solid`: the pastel itself, the same in light and dark mode, for chips,
///   bubbles and buttons, with `onSolid` text on it;
/// - `fill`: a soft surface of the same hue (a light pastel in light mode, the
///   pastel washed over the dark background in dark mode), with `ink` on it.
/// Keeping solid pastels in dark mode is what keeps it from turning muddy.
enum Pastel {
  struct Tone {
    let solid: Color
    let onSolid: Color
    let fill: Color
    let ink: Color
    /// Small highlights (bubbles, status chips): the soft fill in light mode,
    /// the solid pastel in dark mode. Text on it is `onSolid`.
    let chip: Color

    init(solid: Int, lightFill: Int, lightInk: Int) {
      self.solid = Color(hex: solid)
      onSolid = Color(light: lightInk, dark: Pastel.darkText)
      fill = Color(light: lightFill, dark: blend(solid, over: Pastel.darkBackground, 0.3))
      ink = Color(light: lightInk, dark: solid)
      chip = Color(light: lightFill, dark: solid)
    }
  }

  static let darkBackground = 0x14131A
  static let darkText = 0x1A1824

  static let sky = Tone(solid: 0xAFCBFF, lightFill: 0xDEEBFF, lightInk: 0x2F5FC4)
  static let mint = Tone(solid: 0xA3E4C7, lightFill: 0xD8F3E7, lightInk: 0x1F7A55)
  static let peach = Tone(solid: 0xFFC6AB, lightFill: 0xFFE5D7, lightInk: 0xAE4F27)
  static let lavender = Tone(solid: 0xCBBEFF, lightFill: 0xEAE4FF, lightInk: 0x5643BF)
  static let butter = Tone(solid: 0xFFE28F, lightFill: 0xFFF3C6, lightInk: 0x7F6200)
  static let rose = Tone(solid: 0xFFB8CA, lightFill: 0xFFDFE8, lightInk: 0xA9365B)

  /// Periwinkle: a deeper one with white text in light mode, the pastel with
  /// dark text in dark mode.
  static let accent = Color(light: 0x5B6CF0, dark: 0xB4BCFF)
  static let onAccent = Color(light: 0xFFFFFF, dark: darkText)
  static let background = Color(light: 0xF6F5FB, dark: darkBackground)
  static let card = Color(light: 0xFFFFFF, dark: 0x1E1C26)
  static let hairline = Color.primary.opacity(0.07)
  /// Body text on a chip: near black in light mode, the dark text in dark mode.
  static let chipText = Color(light: 0x1C1B22, dark: darkText)

  /// Chart series colors, mid-tone pastels that hold up on white and on dark
  /// cards. Charts pick from the middle (sky) outwards.
  static let chart: [Color] = [
    Color(hex: 0xF29DB5), Color(hex: 0xF4CB63), Color(hex: 0x86D2AE), Color(hex: 0x86B3F5),
    Color(hex: 0xB3A2F0), Color(hex: 0xF5AE8E), Color(hex: 0x7FCFD8),
  ]

  /// The OpenUI components' theme: the accent, card surfaces and the chart
  /// palette above.
  static let openUI: OpenUITheme = {
    var theme = OpenUITheme()
    theme.accent = accent
    theme.onAccent = onAccent
    theme.surface = card
    theme.sunkSurface = Color(light: 0xF1EFF8, dark: 0x282532)
    theme.subtleSurface = Color(light: 0xF7F6FC, dark: 0x22202B)
    theme.border = hairline
    theme.interactiveBorder = Color.primary.opacity(0.12)
    theme.chartPalette = chart
    return theme
  }()
}

/// `color` laid over `background` at `amount` opacity, as one opaque color.
private func blend(_ color: Int, over background: Int, _ amount: Double) -> Int {
  func channel(_ shift: Int) -> Int {
    let top = Double((color >> shift) & 0xFF)
    let bottom = Double((background >> shift) & 0xFF)
    return Int((top * amount + bottom * (1 - amount)).rounded())
  }
  return channel(16) << 16 | channel(8) << 8 | channel(0)
}

extension Color {
  init(hex: Int) {
    self.init(
      red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255)
  }

  /// A color that follows light and dark mode.
  init(light: Int, dark: Int) {
    #if canImport(UIKit)
      self.init(
        uiColor: UIColor { traits in
          UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
        })
    #else
      self.init(
        nsColor: NSColor(name: nil) { appearance in
          let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
          return NSColor(Color(hex: isDark ? dark : light))
        })
    #endif
  }
}
