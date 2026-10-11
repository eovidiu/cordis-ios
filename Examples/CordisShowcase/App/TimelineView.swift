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
    let events = store.snapshot.timeline.reversed().filter { filter.includes($0.kind) }
    NavigationStack {
      List(Array(events.enumerated()), id: \.element.id) { index, event in
        TimelineRow(event: event, isFirst: index == 0, isLast: index == events.count - 1)
          .listRowBackground(Color.clear)
          .listRowSeparator(.hidden)
          .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
      }
      .listStyle(.plain)
      .brandScreen()
      .safeAreaInset(edge: .top, spacing: 0) {
        Picker("Filter", selection: $filter) {
          ForEach(Filter.allCases, id: \.self) { Text($0.rawValue) }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Brand.background)
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
  let isFirst: Bool
  let isLast: Bool

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      // the rail: a dot per event joined by a hairline
      VStack(spacing: 0) {
        Rectangle().fill(isFirst ? .clear : Brand.lineStrong).frame(width: 1, height: 14)
        Circle()
          .fill(color)
          .frame(width: event.kind == .action ? 11 : 8, height: event.kind == .action ? 11 : 8)
          .shadow(color: color.opacity(0.6), radius: event.kind == .action ? 5 : 0)
        Rectangle().fill(isLast ? .clear : Brand.lineStrong).frame(width: 1).frame(maxHeight: .infinity)
      }
      .frame(width: 12)

      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 6) {
          Text(event.date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute().second()))
            .font(Brand.mono(.caption2))
            .foregroundStyle(Brand.dim)
          Tag(text: label, tint: color)
        }
        Text(event.text)
          .font(event.kind == .action ? .callout.weight(.semibold) : Brand.mono(.footnote))
          .foregroundStyle(event.kind == .error ? color : Brand.foreground)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(.top, 9)
      .padding(.bottom, 12)
      Spacer(minLength: 0)
    }
  }

  private var label: String {
    switch event.kind {
    case .action: "you"
    case .status: "internal/status"
    case .plugin: "internal/plugin"
    case .service: "internal/service"
    case .info, .warn, .error, .debug: "log·\(event.kind.rawValue)"
    }
  }

  private var color: Color {
    switch event.kind {
    case .action: Brand.accent
    case .status: EntryState.active.color
    case .plugin: EntryState.unloading.color
    case .service: EntryState.loading.color
    case .info, .debug: Brand.muted
    case .warn: EntryState.pending.color
    case .error: EntryState.failed.color
    }
  }
}
