import ShowcaseKit
import SwiftUI

/// Cards contributed by plugins. The view only renders `snapshot.cards`; a
/// card appears and disappears because the plugin that installed it loaded
/// or unloaded.
struct DashboardView: View {
  @Environment(ShowcaseStore.self) private var store

  var body: some View {
    NavigationStack {
      ScrollView {
        if store.snapshot.cards.isEmpty {
          ContentUnavailableView(
            "No cards",
            systemImage: "square.dashed",
            description: Text("Every card here is an effect of a running plugin. Enable some plugins to fill the dashboard.")
          )
          .padding(.top, 80)
        } else {
          LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
            ForEach(store.snapshot.cards) { card in
              CardView(card: card)
                .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
          }
          .padding()
        }
      }
      .animation(.spring(duration: 0.35), value: store.snapshot.cards.map(\.id))
      .background(Color(.systemGroupedBackground))
      .navigationTitle("Dashboard")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) { BusyIndicator() }
      }
      .safeAreaInset(edge: .bottom) {
        Text("\(store.snapshot.cards.count) cards from \(Set(store.snapshot.cards.map(\.owner)).count) plugins")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .padding(8)
          .frame(maxWidth: .infinity)
          .background(.bar)
      }
    }
  }
}

struct CardView: View {
  @Environment(ShowcaseStore.self) private var store
  let card: Card

  var body: some View {
    let tint = card.content.tint.color
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Image(systemName: card.content.systemImage)
          .font(.title3)
          .foregroundStyle(tint)
        Spacer()
        Text(card.owner)
          .font(.caption2.monospaced())
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      Text(card.title)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
      Text(card.value)
        .font(.title2.bold())
        .contentTransition(.numericText())
        .lineLimit(2)
        .minimumScaleFactor(0.6)
      if !card.detail.isEmpty {
        Text(card.detail)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }
      if !card.actions.isEmpty {
        HStack {
          ForEach(card.actions) { action in
            Button(action.title, systemImage: action.systemImage) {
              store.trigger(action)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .tint(tint)
          }
        }
        .padding(.top, 2)
      }
      Spacer(minLength: 0)
    }
    .padding()
    .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
    .background(
      LinearGradient(colors: [tint.opacity(0.18), tint.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing),
      in: RoundedRectangle(cornerRadius: 18)
    )
    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(tint.opacity(0.25)))
    .animation(.default, value: card.value)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("\(card.title), \(card.value), from \(card.owner)")
  }
}
