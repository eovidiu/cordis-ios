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
          VStack(alignment: .leading, spacing: 6) {
            Label("dashboard", systemImage: "square.grid.2x2").font(.headline)
            Text("Provided by the app on the root context, outside the loader. Every card plugin injects it.")
              .font(.callout)
              .foregroundStyle(.secondary)
          }
        } header: {
          Text("Host service")
        }
        ForEach(realms, id: \.self) { realm in
          Section {
            ForEach(store.snapshot.services.filter { $0.realm == realm }) { service in
              ServiceRowView(service: service)
            }
          } header: {
            Label(realm == "root" ? "Root realm" : "Realm \(realm)", systemImage: "circle.hexagongrid")
          } footer: {
            if realm != "root" {
              Text("An isolated realm: contexts that isolate this name see only the provider in this realm.")
            }
          }
        }
        Section {
          ForEach(store.snapshot.entries.filter { !$0.missing.isEmpty }) { row in
            HStack {
              Text(row.id).font(.body.monospaced())
              Spacer()
              Text("needs \(row.missing.joined(separator: ", "))").foregroundStyle(.orange).font(.callout)
            }
          }
        } header: {
          Text("Unresolved injections")
        } footer: {
          Text("These entries stay pending until a provider for the missing service runs in their realm.")
        }
      }
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
        Text(service.name).font(.headline.monospaced())
        Spacer()
        StateBadge(state: service.state)
      }
      Text("provided by \(service.provider)").font(.callout).foregroundStyle(.secondary)
      if service.consumers.isEmpty {
        Text("no consumers").font(.caption).foregroundStyle(.secondary)
      } else {
        Label("used by \(service.consumers.joined(separator: ", "))", systemImage: "arrow.down.to.line")
          .font(.callout)
          .foregroundStyle(.blue)
      }
    }
    .padding(.vertical, 2)
  }
}
