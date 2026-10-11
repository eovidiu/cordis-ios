import ShowcaseKit
import SwiftUI

/// The website's palette (docs/assets/landing.css), so the app and the site
/// read as one product. The app is dark-only, like the site.
enum Brand {
  static let background = Color(hex: 0x0B0B0F)
  static let backgroundRaised = Color(hex: 0x111117)
  static let panel = Color(hex: 0x16161D)
  static let panelRaised = Color(hex: 0x1C1C25)
  static let line = Color(hex: 0x26262F)
  static let lineStrong = Color(hex: 0x33333F)
  static let foreground = Color(hex: 0xF4F4F7)
  static let muted = Color(hex: 0xA2A2AD)
  static let dim = Color(hex: 0x8A8A95)
  static let accent = Color(hex: 0x8D8BFF)
  static let swift = Color(hex: 0xF05138)
  static let code = Color(hex: 0x1F1F24)

  static let radius: CGFloat = 16
  static func mono(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
    .system(style, design: .monospaced).weight(weight)
  }
}

extension Color {
  init(hex: UInt32) {
    self.init(
      .sRGB,
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255
    )
  }
}

extension CardTint {
  var color: Color {
    switch self {
    case .blue: Color(hex: 0x5AC8FA)
    case .orange: Color(hex: 0xFF9F0A)
    case .green: Color(hex: 0x30D158)
    case .purple: Color(hex: 0xBF5AF2)
    case .pink: Color(hex: 0xFF6482)
    case .teal: Color(hex: 0x40C8E0)
    case .indigo: Brand.accent
    case .gray: Brand.muted
    case .yellow: Color(hex: 0xFFD60A)
    case .red: Color(hex: 0xFF453A)
    case .mint: Color(hex: 0x63E6BE)
    }
  }
}

extension EntryState {
  /// The website's lifecycle pill colours.
  var color: Color {
    switch self {
    case .active: Color(hex: 0x30D158)
    case .loading: Color(hex: 0x5AC8FA)
    case .pending: Color(hex: 0xFFB340)
    case .failed, .unknown: Color(hex: 0xFF453A)
    case .unloading: Color(hex: 0xBF5AF2)
    case .disposed, .disabled, .inactive: Brand.dim
    }
  }

  var symbol: String {
    switch self {
    case .active: "checkmark.circle.fill"
    case .loading: "arrow.triangle.2.circlepath"
    case .pending: "hourglass"
    case .failed: "xmark.octagon.fill"
    case .unknown: "questionmark.diamond.fill"
    case .unloading: "arrow.down.circle"
    case .disposed: "circle.dashed"
    case .disabled: "pause.circle"
    case .inactive: "moon.zzz"
    }
  }

  /// One-line explanation shown in detail views.
  var meaning: String {
    switch self {
    case .active: "The plugin is loaded and its effects are live."
    case .loading: "apply() is running; the fiber becomes active when it returns."
    case .pending: "Waiting until every injected service is available."
    case .failed: "apply() threw. Update the config or restart to retry."
    case .unloading: "Effects are being disposed, newest first."
    case .disposed: "The fiber is gone."
    case .disabled: "The entry is kept but has no fiber."
    case .inactive: "An enclosing group is disabled."
    case .unknown: "The entry names a plugin that is not in the catalog."
    }
  }
}

/// Lifecycle pill, as on the website: monospaced, tinted fill and border.
struct StateBadge: View {
  let state: EntryState

  var body: some View {
    Text(state.rawValue)
      .font(Brand.mono(.caption, weight: .medium))
      .foregroundStyle(state.color)
      .padding(.horizontal, 9)
      .padding(.vertical, 3)
      .background(state.color.opacity(0.1), in: Capsule())
      .overlay(Capsule().strokeBorder(state.color.opacity(0.35)))
      .contentTransition(.interpolate)
      .accessibilityLabel("state \(state.rawValue)")
  }
}

/// Small monospaced tag (service names, owners, kinds).
struct Tag: View {
  let text: String
  var systemImage: String?
  var tint: Color = Brand.muted

  var body: some View {
    HStack(spacing: 4) {
      if let systemImage { Image(systemName: systemImage) }
      Text(text)
    }
    .font(Brand.mono(.caption2, weight: .medium))
    .foregroundStyle(tint)
    .padding(.horizontal, 7)
    .padding(.vertical, 3)
    .background(Brand.panelRaised, in: RoundedRectangle(cornerRadius: 6))
    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Brand.line))
  }
}

/// The website's section kicker: monospaced, uppercase, accent.
struct Kicker: View {
  let text: String
  var body: some View {
    Text(text.uppercased())
      .font(Brand.mono(.caption, weight: .semibold))
      .tracking(1)
      .foregroundStyle(Brand.accent)
  }
}

/// Rounded panel with a hairline border, the site's `.card`.
struct Panel: ViewModifier {
  var highlighted = false
  func body(content: Content) -> some View {
    content
      .background(
        LinearGradient(colors: [Brand.panel, Brand.panel.opacity(0.75)], startPoint: .top, endPoint: .bottom),
        in: RoundedRectangle(cornerRadius: Brand.radius)
      )
      .overlay(
        RoundedRectangle(cornerRadius: Brand.radius)
          .strokeBorder(highlighted ? Brand.accent.opacity(0.6) : Brand.line, lineWidth: highlighted ? 1.5 : 1)
      )
  }
}

extension View {
  func panel(highlighted: Bool = false) -> some View { modifier(Panel(highlighted: highlighted)) }

  /// Dark page chrome shared by every tab.
  func brandScreen() -> some View {
    self
      .scrollContentBackground(.hidden)
      .background(Brand.background)
      .toolbarBackground(Brand.background, for: .navigationBar)
  }
}

/// White capsule, the site's primary button.
struct PrimaryButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.subheadline.weight(.semibold))
      .foregroundStyle(Brand.background)
      .padding(.horizontal, 18)
      .frame(height: 44)
      .frame(maxWidth: .infinity)
      .background(Brand.foreground.opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.35), in: Capsule())
  }
}

/// Outlined capsule, the site's ghost button.
struct GhostButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.subheadline.weight(.semibold))
      .foregroundStyle(Brand.foreground)
      .padding(.horizontal, 14)
      .frame(height: 44)
      .background(Brand.panel.opacity(configuration.isPressed ? 0.6 : 1), in: Capsule())
      .overlay(Capsule().strokeBorder(Brand.lineStrong))
  }
}

/// A tinted SF Symbol in a soft rounded square (Oura / Apple Fitness cards).
struct IconBadge: View {
  let systemImage: String
  let tint: Color
  var size: CGFloat = 34

  var body: some View {
    Image(systemName: systemImage)
      .font(.system(size: size * 0.48, weight: .semibold))
      .foregroundStyle(tint)
      .frame(width: size, height: size)
      .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: size * 0.3))
  }
}

extension PluginInfo {
  static func symbol(for plugin: String) -> String {
    plugin == "group" ? "folder" : ShowcaseCatalog.info(plugin)?.systemImage ?? "puzzlepiece.extension"
  }
}
