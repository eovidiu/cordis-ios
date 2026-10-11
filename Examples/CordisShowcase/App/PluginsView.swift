import ShowcaseKit
import SwiftUI

/// The loader's entry tree with each fiber's live state.
struct PluginsView: View {
  @Environment(ShowcaseStore.self) private var store
  @State private var adding = false
  @State private var confirmReset = false

  var body: some View {
    NavigationStack {
      List {
        Section {
          ForEach(store.snapshot.entries) { row in
            NavigationLink(value: row.id) {
              EntryRowView(row: row)
            }
            .listRowBackground(Brand.panel)
            .listRowSeparatorTint(Brand.line)
            .swipeActions(edge: .trailing) {
              Button("Remove", systemImage: "trash", role: .destructive) {
                Task { await store.run(.remove(row.id)) }
              }
              if row.state == .active || row.state == .failed {
                Button("Restart", systemImage: "arrow.clockwise") {
                  Task { await store.run(.restart(row.id)) }
                }
                .tint(Brand.accent)
              }
            }
          }
        } header: {
          Kicker(text: "\(store.snapshot.entries.count) entries · entries.json")
        } footer: {
          Text("Toggling, editing or removing an entry saves the tree; the loader reconciles the running fibers against it.")
            .foregroundStyle(Brand.dim)
        }
      }
      .animation(.default, value: store.snapshot.entries.map(\.id))
      .brandScreen()
      .navigationTitle("Plugins")
      .navigationDestination(for: String.self) { id in
        EntryDetailView(id: id)
      }
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Reset", systemImage: "arrow.counterclockwise") { confirmReset = true }
        }
        ToolbarItem(placement: .topBarTrailing) { BusyIndicator() }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Add plugin", systemImage: "plus") { adding = true }
        }
      }
      .confirmationDialog("Reconcile to the default entries?", isPresented: $confirmReset, titleVisibility: .visible) {
        Button("Reset entries", role: .destructive) {
          Task { await store.run(.reset) }
        }
      } message: {
        Text("Added entries are disposed, edited configs are restored, untouched entries keep running.")
      }
      .sheet(isPresented: $adding) {
        AddPluginView()
      }
    }
  }
}

struct EntryRowView: View {
  @Environment(ShowcaseStore.self) private var store
  let row: EntryRow

  var body: some View {
    HStack(spacing: 12) {
      IconBadge(systemImage: PluginInfo.symbol(for: row.plugin), tint: row.state.color, size: 32)
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 6) {
          Text(row.id).font(Brand.mono(.body, weight: .medium)).foregroundStyle(Brand.foreground)
          if row.id != row.plugin {
            Text(row.plugin).font(Brand.mono(.caption)).foregroundStyle(Brand.dim)
          }
        }
        StateBadge(state: row.state)
        if !row.missing.isEmpty {
          Text("waiting for \(row.missing.joined(separator: ", "))")
            .font(.caption)
            .foregroundStyle(EntryState.pending.color)
        }
        if let provides = row.provides {
          Text("provides \(provides)")
            .font(.caption)
            .foregroundStyle(Brand.muted)
        }
        if !row.isolation.isEmpty {
          Text(row.isolation.joined(separator: ", "))
            .font(.caption)
            .foregroundStyle(Brand.accent)
        }
      }
      Spacer()
      Toggle("Enabled", isOn: Binding(
        get: { row.state != .disabled },
        set: { enabled in Task { await store.run(.setEnabled(row.id, enabled)) } }
      ))
      .labelsHidden()
      .tint(EntryState.active.color)
      .disabled(row.state == .inactive)
    }
    .padding(.leading, CGFloat(row.depth) * 20)
  }
}

struct EntryDetailView: View {
  @Environment(ShowcaseStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  let id: String
  @State private var draft = ""
  @State private var loadedConfig: String?
  @FocusState private var editing: Bool

  var body: some View {
    if let row = store.snapshot.row(id) {
      form(row)
        .navigationTitle(row.id)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { syncDraft(row.config) }
        .onChange(of: row.config) { _, config in syncDraft(config) }
    } else {
      ContentUnavailableView("Entry removed", systemImage: "trash", description: Text("\(id) is no longer in the tree."))
    }
  }

  /// Follows the persisted config unless the user has unsaved edits.
  private func syncDraft(_ config: String) {
    if loadedConfig == nil || draft == loadedConfig { draft = config }
    loadedConfig = config
  }

  private func form(_ row: EntryRow) -> some View {
    Form {
      Section {
        HStack(spacing: 12) {
          IconBadge(systemImage: PluginInfo.symbol(for: row.plugin), tint: row.state.color)
          StateBadge(state: row.state)
          Spacer()
          Toggle("Enabled", isOn: Binding(
            get: { row.state != .disabled },
            set: { enabled in Task { await store.run(.setEnabled(row.id, enabled)) } }
          ))
          .labelsHidden()
          .tint(EntryState.active.color)
          .disabled(row.state == .inactive)
        }
        Text(row.state.meaning).font(.callout).foregroundStyle(Brand.muted)
        if let error = row.error {
          Label(error, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(EntryState.failed.color)
            .font(.callout)
        }
      } header: {
        Kicker(text: "State")
      }
      .listRowBackground(Brand.panel)

      Section {
        LabeledContent("Catalog name") { Text(row.plugin).font(Brand.mono(.body)) }
        if let info = ShowcaseCatalog.info(row.plugin) {
          Text(info.summary).font(.callout).foregroundStyle(Brand.muted)
        } else if row.isGroup {
          Text("A group runs its child entries under its own fiber.").font(.callout).foregroundStyle(Brand.muted)
        }
        if let provides = row.provides {
          LabeledContent("Provides") { Text(provides).font(Brand.mono(.body)) }
        }
        if let parent = row.parent {
          LabeledContent("Group") { Text(parent).font(Brand.mono(.body)) }
        }
        ForEach(row.isolation, id: \.self) { isolation in
          Label(isolation, systemImage: "circle.hexagongrid").foregroundStyle(Brand.accent)
        }
      } header: {
        Kicker(text: "Plugin")
      }
      .listRowBackground(Brand.panel)

      if !row.dependencies.isEmpty {
        Section {
          ForEach(row.dependencies, id: \.name) { dependency in
            HStack {
              Text(dependency.name).font(Brand.mono(.body))
              Spacer()
              switch dependency.available {
              case true?: Label("available", systemImage: "checkmark.circle.fill").foregroundStyle(EntryState.active.color)
              case false?: Label("missing", systemImage: "xmark.circle.fill").foregroundStyle(EntryState.pending.color)
              case nil: Label("no fiber", systemImage: "minus.circle").foregroundStyle(Brand.dim)
              }
            }
            .font(.callout)
          }
        } header: {
          Kicker(text: "Injected services")
        } footer: {
          Text("The plugin runs only while every injected service is available in its realm.").foregroundStyle(Brand.dim)
        }
        .listRowBackground(Brand.panel)
      }

      if !row.isGroup {
        Section {
          TextEditor(text: $draft)
            .font(Brand.mono(.callout))
            .scrollContentBackground(.hidden)
            .padding(6)
            .background(Brand.code, in: RoundedRectangle(cornerRadius: 10))
            .frame(minHeight: 120)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .focused($editing)
          // Two buttons in one form row need a borderless style, or a tap
          // on the row triggers both.
          HStack {
            Button("Apply config") {
              editing = false
              Task { await store.updateConfig(row.id, text: draft) }
            }
            .fontWeight(.semibold)
            .disabled(draft == row.config)
            Spacer()
            Button("Revert", role: .cancel) {
              editing = false
              draft = row.config
            }
            .disabled(draft == row.config)
          }
          .buttonStyle(.borderless)
        } header: {
          Kicker(text: "Config · JSON")
        } footer: {
          Text("Applying calls fiber.update: the config is validated, then the plugin reloads with it. A rejected config leaves the running instance untouched.")
            .foregroundStyle(Brand.dim)
        }
        .listRowBackground(Brand.panel)
      }

      Section {
        if row.effects.isEmpty {
          Text("No live effects").foregroundStyle(Brand.dim)
        }
        ForEach(Array(row.effects.enumerated()), id: \.offset) { _, effect in
          Text(effect.label)
            .font(Brand.mono(.caption))
            .foregroundStyle(Brand.foreground)
            .padding(.leading, CGFloat(effect.depth) * 14)
        }
      } header: {
        Kicker(text: "Effects · fiber.getEffects()")
      } footer: {
        Text("Everything the plugin installed. Unloading disposes these newest first, which is why disabling a plugin removes its card and listeners.")
          .foregroundStyle(Brand.dim)
      }
      .listRowBackground(Brand.panel)

      Section {
        Button("Restart", systemImage: "arrow.clockwise") {
          Task { await store.run(.restart(row.id)) }
        }
        .disabled(!(row.state == .active || row.state == .failed))
        Button("Remove entry", systemImage: "trash", role: .destructive) {
          Task {
            await store.run(.remove(row.id))
            dismiss()
          }
        }
      }
      .listRowBackground(Brand.panel)
    }
    .brandScreen()
  }
}

struct AddPluginView: View {
  @Environment(ShowcaseStore.self) private var store
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    @Bindable var store = store
    NavigationStack {
      List(ShowcaseCatalog.plugins) { info in
        Button {
          Task {
            await store.run(.add(plugin: info.name, config: nil))
            // a problem is shown in this sheet (the root's alert is covered
            // by it); the sheet closes once the user dismisses the alert
            if store.problem == nil { dismiss() }
          }
        } label: {
          HStack(alignment: .top, spacing: 12) {
            IconBadge(systemImage: info.systemImage, tint: Brand.accent)
            VStack(alignment: .leading, spacing: 5) {
              Text(info.name).font(Brand.mono(.headline, weight: .semibold)).foregroundStyle(Brand.foreground)
              Text(info.summary).font(.callout).foregroundStyle(Brand.muted)
              HStack {
                if let provides = info.provides {
                  Tag(text: "provides \(provides)", tint: EntryState.active.color)
                }
                ForEach(info.injects, id: \.self) { name in
                  Tag(text: name, systemImage: "arrow.down.to.line", tint: EntryState.loading.color)
                }
              }
            }
          }
        }
        .listRowBackground(Brand.panel)
      }
      .brandScreen()
      .navigationTitle("Plugin catalog")
      .alert(item: $store.problem) { problem in
        Alert(title: Text(problem.title), message: Text(problem.message), dismissButton: .default(Text("OK")) { dismiss() })
      }
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
      }
    }
  }
}
