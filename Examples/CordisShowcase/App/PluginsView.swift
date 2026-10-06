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
            .swipeActions(edge: .trailing) {
              Button("Remove", systemImage: "trash", role: .destructive) {
                Task { await store.run(.remove(row.id)) }
              }
              if row.state == .active || row.state == .failed {
                Button("Restart", systemImage: "arrow.clockwise") {
                  Task { await store.run(.restart(row.id)) }
                }
                .tint(.blue)
              }
            }
          }
        } footer: {
          Text("Entries are persisted in entries.json. Toggling, editing or removing an entry saves the tree and the loader reconciles the running fibers against it.")
        }
      }
      .animation(.default, value: store.snapshot.entries.map(\.id))
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
      Image(systemName: PluginInfo.symbol(for: row.plugin))
        .font(.title3)
        .foregroundStyle(row.state.color)
        .frame(width: 28)
      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 6) {
          Text(row.id).font(.body.weight(.medium))
          if row.id != row.plugin {
            Text(row.plugin).font(.caption.monospaced()).foregroundStyle(.secondary)
          }
        }
        StateBadge(state: row.state)
        if !row.missing.isEmpty {
          Text("waiting for \(row.missing.joined(separator: ", "))")
            .font(.caption)
            .foregroundStyle(.orange)
        }
        if let provides = row.provides {
          Text("provides \(provides)")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        if !row.isolation.isEmpty {
          Text(row.isolation.joined(separator: ", "))
            .font(.caption)
            .foregroundStyle(.indigo)
        }
      }
      Spacer()
      Toggle("Enabled", isOn: Binding(
        get: { row.state != .disabled },
        set: { enabled in Task { await store.run(.setEnabled(row.id, enabled)) } }
      ))
      .labelsHidden()
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
      Section("State") {
        HStack {
          StateBadge(state: row.state)
          Spacer()
          Toggle("Enabled", isOn: Binding(
            get: { row.state != .disabled },
            set: { enabled in Task { await store.run(.setEnabled(row.id, enabled)) } }
          ))
          .labelsHidden()
          .disabled(row.state == .inactive)
        }
        Text(row.state.meaning).font(.callout).foregroundStyle(.secondary)
        if let error = row.error {
          Label(error, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
            .font(.callout)
        }
      }

      Section("Plugin") {
        LabeledContent("Catalog name", value: row.plugin)
        if let info = ShowcaseCatalog.info(row.plugin) {
          Text(info.summary).font(.callout)
        } else if row.isGroup {
          Text("A group runs its child entries under its own fiber.").font(.callout)
        }
        if let provides = row.provides {
          LabeledContent("Provides", value: provides)
        }
        if let parent = row.parent {
          LabeledContent("Group", value: parent)
        }
        ForEach(row.isolation, id: \.self) { isolation in
          Label(isolation, systemImage: "circle.hexagongrid").foregroundStyle(.indigo)
        }
      }

      if !row.dependencies.isEmpty {
        Section {
          ForEach(row.dependencies, id: \.name) { dependency in
            HStack {
              Text(dependency.name).font(.body.monospaced())
              Spacer()
              switch dependency.available {
              case true?: Label("available", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
              case false?: Label("missing", systemImage: "xmark.circle.fill").foregroundStyle(.orange)
              case nil: Label("no fiber", systemImage: "minus.circle").foregroundStyle(.secondary)
              }
            }
            .font(.callout)
          }
        } header: {
          Text("Injected services")
        } footer: {
          Text("The plugin runs only while every injected service is available in its realm.")
        }
      }

      if !row.isGroup {
        Section {
          TextEditor(text: $draft)
            .font(.callout.monospaced())
            .frame(minHeight: 110)
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
          Text("Config (JSON)")
        } footer: {
          Text("Applying calls fiber.update: the config is validated, then the plugin reloads with it. A rejected config leaves the running instance untouched.")
        }
      }

      Section {
        if row.effects.isEmpty {
          Text("No live effects").foregroundStyle(.secondary)
        }
        ForEach(Array(row.effects.enumerated()), id: \.offset) { _, effect in
          Text(effect.label)
            .font(.caption.monospaced())
            .padding(.leading, CGFloat(effect.depth) * 14)
        }
      } header: {
        Text("Effects (fiber.getEffects())")
      } footer: {
        Text("Everything the plugin installed. Unloading disposes these newest first, which is why disabling a plugin removes its card and listeners.")
      }

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
    }
  }
}

struct AddPluginView: View {
  @Environment(ShowcaseStore.self) private var store
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List(ShowcaseCatalog.plugins) { info in
        Button {
          Task {
            await store.run(.add(plugin: info.name, config: nil))
            dismiss()
          }
        } label: {
          HStack(alignment: .top, spacing: 12) {
            Image(systemName: info.systemImage)
              .font(.title3)
              .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
              Text(info.name).font(.headline)
              Text(info.summary).font(.callout).foregroundStyle(.secondary)
              HStack {
                if let provides = info.provides {
                  Tag(text: "provides \(provides)", tint: .green)
                }
                ForEach(info.injects, id: \.self) { name in
                  Tag(text: name, systemImage: "arrow.down.to.line", tint: .blue)
                }
              }
            }
          }
        }
        .foregroundStyle(.primary)
      }
      .navigationTitle("Plugin catalog")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
      }
    }
  }
}
