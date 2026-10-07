import ShowcaseKit
import SwiftUI

/// Walks through the plugin system one operation at a time. Each step shows
/// the live state of the entries it touches, so the effect of running it is
/// visible right on the card.
struct TourView: View {
  @Environment(ShowcaseStore.self) private var store
  @Binding var tab: AppTab
  @State private var completed: Set<Int> = []
  @State private var running: Int?
  /// `-showAbout YES` opens the credits at launch (screenshots, UI tests).
  @State private var showingAbout = UserDefaults.standard.bool(forKey: "showAbout")

  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 16) {
          intro
          ForEach(TourStep.all) { step in
            TourStepCard(
              step: step,
              isDone: completed.contains(step.id),
              isRunning: running == step.id,
              isNext: step.id == nextStep,
              run: { run(step) },
              showDashboard: { tab = .dashboard }
            )
          }
          credits
        }
        .padding()
      }
      .background(Color(.systemGroupedBackground))
      .navigationTitle("Cordis Tour")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) { BusyIndicator() }
        ToolbarItem(placement: .topBarTrailing) {
          Button("About", systemImage: "info.circle") { showingAbout = true }
        }
        ToolbarItem(placement: .topBarLeading) {
          if !completed.isEmpty {
            Button("Restart tour") { completed = [] }
          }
        }
      }
      .sheet(isPresented: $showingAbout) { AboutView() }
    }
  }

  private var nextStep: Int? {
    TourStep.all.first { !completed.contains($0.id) }?.id
  }

  private var intro: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("An app made of plugins")
        .font(.title2.bold())
      Text("Every card on the Dashboard is contributed by a plugin running in cordis. Plugins declare the services they need; cordis loads them when those services exist, unloads them when they go away, and undoes everything a plugin did when it stops.")
        .font(.callout)
        .foregroundStyle(.secondary)
      Text("Run the steps in order and watch the entries change state.")
        .font(.callout)
        .foregroundStyle(.secondary)
    }
    .padding(.bottom, 4)
  }

  private var credits: some View {
    Button { showingAbout = true } label: {
      HStack(spacing: 12) {
        Image(systemName: "heart.text.square")
          .font(.title2)
        VStack(alignment: .leading, spacing: 2) {
          Text("Credits").font(.headline)
          Text("cordis by Shigma and the cordiverse contributors, the paper behind it, and the Swift port on GitHub.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
        }
        Spacer()
        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
      }
      .padding()
      .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Credits")
  }

  private func run(_ step: TourStep) {
    running = step.id
    Task {
      for operation in step.operations {
        await store.run(operation)
      }
      running = nil
      completed.insert(step.id)
    }
  }
}

private struct TourStepCard: View {
  @Environment(ShowcaseStore.self) private var store
  let step: TourStep
  let isDone: Bool
  let isRunning: Bool
  let isNext: Bool
  let run: () -> Void
  let showDashboard: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline) {
        Text("\(step.id)")
          .font(.headline.monospacedDigit())
          .foregroundStyle(.white)
          .frame(width: 28, height: 28)
          .background(isDone ? Color.green : Color.accentColor, in: Circle())
        VStack(alignment: .leading, spacing: 2) {
          Text(step.title).font(.headline)
          Tag(text: step.concept, systemImage: "lightbulb", tint: .accentColor)
        }
        Spacer()
        if isDone {
          Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        }
      }
      Text(step.explanation)
        .font(.subheadline)
        .fixedSize(horizontal: false, vertical: true)
      entries
      if isDone {
        Label(step.observe, systemImage: "eye")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          .transition(.opacity)
      }
      HStack {
        Button(action: run) {
          if isRunning {
            ProgressView().frame(maxWidth: .infinity)
          } else {
            Label(isDone ? "Run again" : "Run step", systemImage: "play.fill")
              .frame(maxWidth: .infinity)
          }
        }
        .buttonStyle(.borderedProminent)
        .tint(isNext ? .accentColor : .secondary)
        .disabled(isRunning || store.isBusy)
        Button("Dashboard", systemImage: "square.grid.2x2", action: showDashboard)
          .buttonStyle(.bordered)
          .labelStyle(.iconOnly)
          .accessibilityLabel("Show dashboard")
      }
    }
    .padding()
    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    .overlay {
      RoundedRectangle(cornerRadius: 16)
        .strokeBorder(isNext ? Color.accentColor.opacity(0.5) : .clear, lineWidth: 1.5)
    }
    .animation(.default, value: isDone)
  }

  /// Live state of the entries this step is about.
  private var entries: some View {
    let ids = (step.expectedStates ?? [:]).keys.sorted()
    return FlowLayout(spacing: 6) {
      ForEach(ids, id: \.self) { id in
        HStack(spacing: 4) {
          Text(id).font(.caption.monospaced())
          if let row = store.snapshot.row(id) {
            StateBadge(state: row.state)
          } else {
            Tag(text: "absent", tint: .gray)
          }
        }
        .fixedSize()
        .animation(.default, value: store.snapshot.row(id)?.state)
      }
    }
  }
}

/// Wraps its children onto as many lines as needed.
struct FlowLayout: Layout {
  var spacing: CGFloat = 8

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let rows = arrange(proposal: proposal, subviews: subviews)
    let width = rows.map(\.width).max() ?? 0
    let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
    return CGSize(width: proposal.width ?? width, height: height)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    var y = bounds.minY
    for row in arrange(proposal: proposal, subviews: subviews) {
      var x = bounds.minX
      for index in row.indices {
        let size = subviews[index].sizeThatFits(.unspecified)
        subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
        x += size.width + spacing
      }
      y += row.height + spacing
    }
  }

  private struct Row {
    var indices: [Int] = []
    var width: CGFloat = 0
    var height: CGFloat = 0
  }

  private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
    let maxWidth = proposal.width ?? .infinity
    var rows: [Row] = [Row()]
    for index in subviews.indices {
      let size = subviews[index].sizeThatFits(.unspecified)
      if !rows[rows.count - 1].indices.isEmpty && rows[rows.count - 1].width + spacing + size.width > maxWidth {
        rows.append(Row())
      }
      var row = rows[rows.count - 1]
      row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
      row.height = max(row.height, size.height)
      row.indices.append(index)
      rows[rows.count - 1] = row
    }
    return rows
  }
}
