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
        VStack(alignment: .leading, spacing: 14) {
          HStack(alignment: .firstTextBaseline) {
            Kicker(text: "Effects on screen")
            Spacer()
            Text("\(store.snapshot.cards.count) cards · \(Set(store.snapshot.cards.map(\.owner)).count) plugins")
              .font(Brand.mono(.caption))
              .foregroundStyle(Brand.dim)
          }
          if store.snapshot.cards.isEmpty {
            ContentUnavailableView(
              "No cards",
              systemImage: "square.dashed",
              description: Text("Every card here is an effect of a running plugin. Enable some plugins to fill the dashboard.")
            )
            .padding(.top, 60)
          } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
              ForEach(store.snapshot.cards) { card in
                CardView(card: card)
                  .transition(.scale(scale: 0.9).combined(with: .opacity))
              }
            }
          }
        }
        .padding()
      }
      .animation(.spring(duration: 0.35), value: store.snapshot.cards.map(\.id))
      .brandScreen()
      .navigationTitle("Dashboard")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) { BusyIndicator() }
      }
    }
  }
}

struct CardView: View {
  @Environment(ShowcaseStore.self) private var store
  let card: Card

  var body: some View {
    let tint = card.content.tint.color
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .top) {
        IconBadge(systemImage: card.content.systemImage, tint: tint)
        Spacer()
        Tag(text: card.owner)
      }
      Text(card.title)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Brand.muted)
        .padding(.top, 4)
      Text(card.value)
        .font(.system(.title2, design: .rounded).weight(.bold))
        .foregroundStyle(tint)
        .contentTransition(.numericText())
        .lineLimit(2)
        .minimumScaleFactor(0.6)
      if !card.detail.isEmpty {
        Text(card.detail)
          .font(.caption)
          .foregroundStyle(Brand.dim)
          .lineLimit(2)
      }
      Spacer(minLength: 0)
      if !card.actions.isEmpty {
        HStack(spacing: 8) {
          ForEach(card.actions) { action in
            Button(action.title, systemImage: action.systemImage) {
              store.trigger(action)
            }
            .labelStyle(.iconOnly)
            .font(.body.weight(.semibold))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(tint.opacity(0.14), in: Capsule())
          }
        }
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
    .background(
      RadialGradient(colors: [tint.opacity(0.16), .clear], center: .topLeading, startRadius: 0, endRadius: 180),
      in: RoundedRectangle(cornerRadius: Brand.radius)
    )
    .panel()
    .animation(.default, value: card.value)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("\(card.title), \(card.value), from \(card.owner)")
  }
}
