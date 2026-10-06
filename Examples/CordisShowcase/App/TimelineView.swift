import ShowcaseKit
import SwiftUI

/// cordis's internal events (internal/status, internal/plugin,
/// internal/service), logger output and user actions, newest first.
struct TimelineView: View {
  @Environment(ShowcaseStore.self) private var store
  @State private var filter: Filter = .all

  enum Filter: String, CaseIterable {
    case all = "All"
    case lifecycle = "Lifecycle"
    case services = "Services"
    case logs = "Logs"

    func includes(_ kind: TimelineEvent.Kind) -> Bool {
      switch self {
      case .all: true
      case .lifecycle: kind == .status || kind == .plugin || kind == .action
      case .services: kind == .service || kind == .action
      case .logs: kind == .info || kind == .warn || kind == .error || kind == .debug || kind == .action
      }
    }
  }

  var body: some View {
    NavigationStack {
      List(store.snapshot.timeline.reversed().filter { filter.includes($0.kind) }) { event in
        TimelineRow(event: event)
      }
      .listStyle(.plain)
      .safeAreaInset(edge: .top) {
        Picker("Filter", selection: $filter) {
          ForEach(Filter.allCases, id: \.self) { Text($0.rawValue) }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
      }
      .navigationTitle("Timeline")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) { BusyIndicator() }
      }
    }
  }
}

private struct TimelineRow: View {
  let event: TimelineEvent

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Image(systemName: symbol)
        .foregroundStyle(color)
        .frame(width: 18)
      VStack(alignment: .leading, spacing: 2) {
        Text(event.text)
          .font(event.kind == .action ? .callout.weight(.semibold) : .callout.monospaced())
          .foregroundStyle(event.kind == .error ? .red : .primary)
        Text("\(event.date.formatted(date: .omitted, time: .standard)) · \(label)")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
    .listRowBackground(event.kind == .action ? Color.accentColor.opacity(0.08) : nil)
  }

  private var label: String {
    switch event.kind {
    case .action: "you"
    case .status: "internal/status"
    case .plugin: "internal/plugin"
    case .service: "internal/service"
    case .info, .warn, .error, .debug: "logger · \(event.kind.rawValue)"
    }
  }

  private var symbol: String {
    switch event.kind {
    case .action: "hand.tap"
    case .status: "arrow.right.circle"
    case .plugin: "puzzlepiece.extension"
    case .service: "point.3.connected.trianglepath.dotted"
    case .info, .debug: "text.bubble"
    case .warn: "exclamationmark.bubble"
    case .error: "exclamationmark.octagon"
    }
  }

  private var color: Color {
    switch event.kind {
    case .action: .accentColor
    case .status: .green
    case .plugin: .purple
    case .service: .blue
    case .info, .debug: .secondary
    case .warn: .orange
    case .error: .red
    }
  }
}
