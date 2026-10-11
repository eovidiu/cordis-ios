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
      .brandScreen()
      .navigationTitle("Tour")
      .navigationBarTitleDisplayMode(.inline)
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

  /// The website hero, condensed: eyebrow pill, gradient headline, lede.
  private var intro: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 7) {
        Circle().fill(Color(hex: 0x3DDC84)).frame(width: 7, height: 7)
          .shadow(color: Color(hex: 0x3DDC84), radius: 4)
        Text("Swift 6 · cordis-ios · MIT").font(Brand.mono(.caption2))
      }
      .foregroundStyle(Brand.muted)
      .padding(.horizontal, 11)
      .padding(.vertical, 5)
      .overlay(Capsule().strokeBorder(Brand.lineStrong))
      Text("Plugins that clean up after themselves.")
        .font(.system(.largeTitle, design: .default).weight(.bold))
        .tracking(-0.8)
        .foregroundStyle(LinearGradient(colors: [.white, Color(hex: 0xB7B6C8)], startPoint: .top, endPoint: .bottom))
        .fixedSize(horizontal: false, vertical: true)
      Text("Every card on the Dashboard comes from a plugin. Plugins declare the services they need; cordis loads them when those services exist, unloads them when they go away, and undoes everything a plugin did when it stops.")
        .font(.callout)
        .foregroundStyle(Brand.muted)
      Kicker(text: "Run the steps in order").padding(.top, 6)
    }
    .padding(.bottom, 4)
    .background(alignment: .topLeading) {
      RadialGradient(colors: [Color(hex: 0x6E6AF0).opacity(0.28), .clear], center: .topLeading, startRadius: 0, endRadius: 260)
        .frame(width: 520, height: 360)
        .offset(x: -120, y: -140)
        .allowsHitTesting(false)
    }
  }

  private var credits: some View {
    Button { showingAbout = true } label: {
      HStack(spacing: 12) {
        IconBadge(systemImage: "heart.text.square", tint: Brand.accent)
        VStack(alignment: .leading, spacing: 3) {
          Kicker(text: "Built on research")
          Text("cordis by Shigma and the cordiverse contributors, the paper behind it, and the Swift port on GitHub.")
            .font(.caption)
            .foregroundStyle(Brand.muted)
            .multilineTextAlignment(.leading)
        }
        Spacer()
        Image(systemName: "chevron.right").foregroundStyle(Brand.dim)
      }
      .padding()
      .panel()
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
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .center, spacing: 10) {
        Text("\(step.id)")
          .font(Brand.mono(.subheadline, weight: .semibold))
          .foregroundStyle(isDone ? EntryState.active.color : Brand.accent)
          .frame(width: 30, height: 30)
          .background(Brand.panelRaised, in: RoundedRectangle(cornerRadius: 9))
          .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Brand.lineStrong))
        VStack(alignment: .leading, spacing: 2) {
          Kicker(text: step.concept)
          Text(step.title).font(.headline).foregroundStyle(Brand.foreground)
        }
        Spacer()
        if isDone {
          Image(systemName: "checkmark.circle.fill").foregroundStyle(EntryState.active.color)
        }
      }
      Text(step.explanation)
        .font(.subheadline)
        .foregroundStyle(Brand.muted)
        .fixedSize(horizontal: false, vertical: true)
      entries
      if isDone {
        Label(step.observe, systemImage: "eye")
          .font(.subheadline)
          .foregroundStyle(Brand.foreground)
          .padding(10)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(Brand.code, in: RoundedRectangle(cornerRadius: 10))
          .fixedSize(horizontal: false, vertical: true)
          .transition(.opacity)
      }
      HStack(spacing: 10) {
        Button(action: run) {
          if isRunning {
            ProgressView().tint(Brand.background)
          } else {
            Label(isDone ? "Run again" : "Run step", systemImage: "play.fill")
          }
        }
        .buttonStyle(PrimaryButtonStyle())
        .opacity(isNext || isDone ? 1 : 0.75)
        .disabled(isRunning || store.isBusy)
        Button("Dashboard", systemImage: "square.grid.2x2", action: showDashboard)
          .labelStyle(.iconOnly)
          .buttonStyle(GhostButtonStyle())
          .accessibilityLabel("Show dashboard")
      }
    }
    .padding()
    .panel(highlighted: isNext)
    .animation(.default, value: isDone)
  }

  /// Live state of the entries this step is about.
  private var entries: some View {
    let ids = (step.expectedStates ?? [:]).keys.sorted()
    return FlowLayout(spacing: 6) {
      ForEach(ids, id: \.self) { id in
        HStack(spacing: 4) {
          Text(id).font(Brand.mono(.caption)).foregroundStyle(Brand.foreground)
          if let row = store.snapshot.row(id) {
            StateBadge(state: row.state)
          } else {
            Tag(text: "absent", tint: Brand.dim)
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
