import ShowcaseKit
import SwiftUI

/// Services by realm: who provides each one and who consumes it.
struct ServicesView: View {
  @Environment(ShowcaseStore.self) private var store

  private var realms: [String] {
    Array(Set(store.snapshot.services.map(\.realm))).sorted { lhs, rhs in
      lhs == "root" ? true : rhs == "root" ? false : lhs < rhs
    }
  }

  var body: some View {
    NavigationStack {
      List {
        Section {
          HStack(alignment: .top, spacing: 12) {
            IconBadge(systemImage: "square.grid.2x2", tint: Brand.accent)
            VStack(alignment: .leading, spacing: 4) {
              Text("dashboard").font(Brand.mono(.headline, weight: .semibold)).foregroundStyle(Brand.foreground)
              Text("Provided by the app on the root context, outside the loader. Every card plugin injects it.")
                .font(.callout)
                .foregroundStyle(Brand.muted)
            }
          }
          .padding(.vertical, 2)
        } header: {
          Kicker(text: "Host service")
        }
        .listRowBackground(Brand.panel)

        ForEach(realms, id: \.self) { realm in
          Section {
            ForEach(store.snapshot.services.filter { $0.realm == realm }) { service in
              ServiceRowView(service: service)
            }
          } header: {
            Kicker(text: realm == "root" ? "Root realm" : "Realm \(realm)")
          } footer: {
            if realm != "root" {
              Text("An isolated realm: contexts that isolate this name see only the provider in this realm.")
                .foregroundStyle(Brand.dim)
            }
          }
          .listRowBackground(Brand.panel)
        }

        Section {
          let unresolved = store.snapshot.entries.filter { !$0.missing.isEmpty }
          if unresolved.isEmpty {
            Label("Every injection is resolved", systemImage: "checkmark.circle.fill")
              .foregroundStyle(EntryState.active.color)
              .font(.callout)
          }
          ForEach(unresolved) { row in
            HStack {
              Text(row.id).font(Brand.mono(.body)).foregroundStyle(Brand.foreground)
              Spacer()
              Text("needs \(row.missing.joined(separator: ", "))")
                .font(Brand.mono(.caption))
                .foregroundStyle(EntryState.pending.color)
            }
          }
        } header: {
          Kicker(text: "Unresolved injections")
        } footer: {
          Text("These entries stay pending until a provider for the missing service runs in their realm.")
            .foregroundStyle(Brand.dim)
        }
        .listRowBackground(Brand.panel)
      }
      .brandScreen()
      .navigationTitle("Services")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) { BusyIndicator() }
      }
    }
  }
}

private struct ServiceRowView: View {
  let service: ServiceRow

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(service.name).font(Brand.mono(.headline, weight: .semibold)).foregroundStyle(Brand.foreground)
        Spacer()
        StateBadge(state: service.state)
      }
      Text("provided by \(service.provider)").font(.callout).foregroundStyle(Brand.muted)
      if service.consumers.isEmpty {
        Text("no consumers").font(.caption).foregroundStyle(Brand.dim)
      } else {
        Label("used by \(service.consumers.joined(separator: ", "))", systemImage: "arrow.down.to.line")
          .font(.callout)
          .foregroundStyle(EntryState.loading.color)
      }
    }
    .padding(.vertical, 2)
  }
}
