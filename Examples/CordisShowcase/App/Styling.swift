import ShowcaseKit
import SwiftUI

extension CardTint {
  var color: Color {
    switch self {
    case .blue: .blue
    case .orange: .orange
    case .green: .green
    case .purple: .purple
    case .pink: .pink
    case .teal: .teal
    case .indigo: .indigo
    case .gray: .gray
    case .yellow: .yellow
    case .red: .red
    case .mint: .mint
    }
  }
}

extension EntryState {
  var color: Color {
    switch self {
    case .active: .green
    case .loading: .blue
    case .pending: .orange
    case .failed, .unknown: .red
    case .unloading: .purple
    case .disposed, .disabled, .inactive: .gray
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

/// Coloured capsule naming an entry state.
struct StateBadge: View {
  let state: EntryState

  var body: some View {
    Label(state.rawValue, systemImage: state.symbol)
      .font(.caption.weight(.semibold))
      .foregroundStyle(state.color)
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .background(state.color.opacity(0.15), in: Capsule())
      .contentTransition(.symbolEffect(.replace))
      .accessibilityLabel("state \(state.rawValue)")
  }
}

/// A small tag (service names, concepts).
struct Tag: View {
  let text: String
  var systemImage: String?
  var tint: Color = .secondary

  var body: some View {
    Group {
      if let systemImage {
        Label(text, systemImage: systemImage)
      } else {
        Text(text)
      }
    }
    .font(.caption)
    .foregroundStyle(tint)
    .padding(.horizontal, 7)
    .padding(.vertical, 2)
    .background(tint.opacity(0.12), in: Capsule())
  }
}

extension PluginInfo {
  static func symbol(for plugin: String) -> String {
    plugin == "group" ? "folder" : ShowcaseCatalog.info(plugin)?.systemImage ?? "puzzlepiece.extension"
  }
}
