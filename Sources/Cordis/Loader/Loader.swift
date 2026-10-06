/// Runs a persisted tree of plugin entries (port of the cordis loader,
/// paper §5.2.1, without hot module reload and without Algorithm 7: a change
/// to an entry's `isolate` rebuilds the entry's fiber instead of reassigning
/// realms in place).
///
/// Reconciliation is keyed by entry id: a changed `plugin` or `isolate`
/// disposes and recreates the fiber; a changed `config` calls
/// `fiber.update(config, noSave: true)`; `disabled` disposes the fiber and
/// keeps the entry; removed ids are disposed and new ids created. Group
/// entries (`children`) run the built-in group plugin, which reconciles the
/// children the same way. An entry whose plugin is not in the catalog is
/// logged and kept without a fiber. Every mutation saves the whole tree.
@CordisActor
public final class Loader {
  public let ctx: Context
  public let catalog: PluginCatalog
  private let store: any EntryStore
  public private(set) var entries: [Entry] = []
  private var root: EntryReconciler!
  private var localRealms: [String: Realm] = [:]
  private var sharedRealms: [String: Realm] = [:]
  private var listener: EffectHandle?

  public init(ctx: Context, catalog: PluginCatalog, store: any EntryStore) {
    self.ctx = ctx
    self.catalog = catalog
    self.store = store
    self.root = EntryReconciler(ctx: ctx, loader: self)
  }

  /// Loads the stored entries, runs them, and starts writing configs
  /// changed through `fiber.update` back to their entries.
  public func start() async throws {
    entries = try store.load()
    if listener == nil {
      listener = try ctx.on(UpdateEvent.self, options: EventOptions(global: true)) { [weak self] args, next in
        try await next()
        guard let self, !args.noSave, let id = self.root.entryID(of: args.fiber) else { return }
        try self.persistConfig(args.config, of: id)
      }
    }
    await apply()
  }

  /// Replaces the whole entry tree.
  public func reconcile(_ entries: [Entry]) async throws {
    self.entries = entries
    try store.save(entries)
    await apply()
  }

  /// Adds `entry` at the top level or to the group `parent`.
  public func add(_ entry: Entry, parent: String? = nil) async throws {
    if let parent {
      try mutate(parent) { group in group.children = (group.children ?? []) + [entry] }
    } else {
      entries.append(entry)
    }
    try store.save(entries)
    await apply()
  }

  public func remove(id: String) async throws {
    guard Self.remove(id, from: &entries) else { throw LoaderError.unknownEntry(id) }
    try store.save(entries)
    await apply()
  }

  public func update(id: String, config: JSONValue?) async throws {
    try mutate(id) { $0.config = config }
    try store.save(entries)
    await apply()
  }

  public func setDisabled(id: String, _ disabled: Bool) async throws {
    try mutate(id) { $0.disabled = disabled }
    try store.save(entries)
    await apply()
  }

  /// The running fiber of entry `id`, if any.
  public func fiber(for id: String) -> Fiber? {
    root.node(for: id)?.fiber
  }

  /// Entry `id` anywhere in the tree.
  public func entry(_ id: String) -> Entry? {
    Self.find(id, in: entries)
  }

  // MARK: - internals

  private func apply() async {
    await root.reconcile(entries)
    pruneSharedRealms()
  }

  private func persistConfig(_ config: (any Sendable)?, of id: String) throws {
    let json: JSONValue?
    switch config {
    case nil: json = nil
    case let value as JSONValue: json = value
    case let value as any Encodable: json = try JSONValue(encoding: value)
    default: return
    }
    try mutate(id) { $0.config = json }
    root.node(for: id)?.entry.config = json
    try store.save(entries)
  }

  private func mutate(_ id: String, _ body: (inout Entry) -> Void) throws {
    guard Self.mutate(id, in: &entries, body) else { throw LoaderError.unknownEntry(id) }
  }

  func context(for entry: Entry, parent: Context) -> Context {
    var ctx = parent
    for (name, spec) in (entry.isolate ?? [:]).sorted(by: { $0.key < $1.key }) {
      let realm: Realm
      switch spec {
      case .local:
        let key = "\(entry.id):\(name)"
        if let existing = localRealms[key] {
          realm = existing
        } else {
          realm = parent.makeRealm(name: key)
          localRealms[key] = realm
        }
      case .shared(let shared):
        if let existing = sharedRealms[shared] {
          realm = existing
        } else {
          realm = parent.makeRealm(name: shared)
          sharedRealms[shared] = realm
        }
      }
      ctx = ctx.isolate(name, realm: realm)
    }
    return ctx
  }

  private func pruneSharedRealms() {
    var used: Set<String> = []
    func collect(_ entries: [Entry]) {
      for entry in entries {
        for spec in (entry.isolate ?? [:]).values {
          if case .shared(let name) = spec { used.insert(name) }
        }
        collect(entry.children ?? [])
      }
    }
    collect(entries)
    sharedRealms = sharedRealms.filter { used.contains($0.key) }
  }

  private static func find(_ id: String, in entries: [Entry]) -> Entry? {
    for entry in entries {
      if entry.id == id { return entry }
      if let found = find(id, in: entry.children ?? []) { return found }
    }
    return nil
  }

  private static func mutate(_ id: String, in entries: inout [Entry], _ body: (inout Entry) -> Void) -> Bool {
    for index in entries.indices {
      if entries[index].id == id {
        body(&entries[index])
        return true
      }
      if var children = entries[index].children, mutate(id, in: &children, body) {
        entries[index].children = children
        return true
      }
    }
    return false
  }

  private static func remove(_ id: String, from entries: inout [Entry]) -> Bool {
    if let index = entries.firstIndex(where: { $0.id == id }) {
      entries.remove(at: index)
      return true
    }
    for index in entries.indices {
      if var children = entries[index].children, remove(id, from: &children) {
        entries[index].children = children
        return true
      }
    }
    return false
  }
}

public enum LoaderError: Error, Equatable, CustomStringConvertible {
  case unknownEntry(String)

  public var description: String {
    switch self {
    case .unknownEntry(let id): "unknown entry \"\(id)\""
    }
  }
}

/// Runtime state of one entry.
@CordisActor
final class EntryNode {
  var entry: Entry
  var fiber: Fiber?
  /// Reconciler of a running group's children.
  var children: EntryReconciler?

  init(entry: Entry) {
    self.entry = entry
  }
}

/// Keeps the fibers of one entry list (top level or a group's children) in
/// line with the entries.
@CordisActor
final class EntryReconciler {
  let ctx: Context
  unowned let loader: Loader
  private var nodes: [String: EntryNode] = [:]

  init(ctx: Context, loader: Loader) {
    self.ctx = ctx
    self.loader = loader
  }

  func node(for id: String) -> EntryNode? {
    if let node = nodes[id] { return node }
    for node in nodes.values {
      if let found = node.children?.node(for: id) { return found }
    }
    return nil
  }

  func entryID(of fiber: Fiber) -> String? {
    for node in nodes.values {
      if node.fiber === fiber { return node.entry.id }
      if let id = node.children?.entryID(of: fiber) { return id }
    }
    return nil
  }

  func reconcile(_ entries: [Entry]) async {
    let ids = Set(entries.map(\.id))
    for (id, node) in nodes where !ids.contains(id) {
      nodes[id] = nil
      await stop(node)
    }
    for entry in entries {
      guard let node = nodes[entry.id] else {
        let node = EntryNode(entry: entry)
        nodes[entry.id] = node
        start(node)
        continue
      }
      let old = node.entry
      node.entry = entry
      if old.plugin != entry.plugin || old.isolate != entry.isolate || old.disabled != entry.disabled
        || (old.children == nil) != (entry.children == nil) {
        await stop(node)
        start(node)
      } else if let fiber = node.fiber {
        if old.config != entry.config && entry.children == nil {
          do {
            try await fiber.update(entry.config, noSave: true)
          } catch {
            // the fiber has logged a failed reload; log validation errors here
            if error is ValidationError { ctx.logger.error(error) }
          }
        }
        if old.children != entry.children, let children = node.children {
          await children.reconcile(entry.children ?? [])
        }
      }
    }
    await settle()
  }

  func disposeAll() async {
    for node in nodes.values {
      await stop(node)
    }
    nodes.removeAll()
  }

  private func start(_ node: EntryNode) {
    let entry = node.entry
    if entry.disabled { return }
    let plugin: any AnyPlugin
    if entry.children != nil {
      plugin = GroupPlugin.make(node: node, loader: loader)
    } else if let resolved = loader.catalog.resolve(entry.plugin) {
      plugin = resolved
    } else {
      ctx.logger.error("plugin \"\(entry.plugin)\" is not in the catalog")
      return
    }
    let entryCtx = loader.context(for: entry, parent: ctx)
    do {
      node.fiber = try entryCtx.plugin(plugin, rawConfig: entry.children == nil ? entry.config : nil)
    } catch {
      ctx.logger.error(error)
    }
  }

  private func stop(_ node: EntryNode) async {
    guard let fiber = node.fiber else { return }
    node.fiber = nil
    try? await fiber.dispose()
  }

  /// Waits for every fiber of this list, then for the children of groups.
  private func settle() async {
    for node in nodes.values {
      _ = try? await node.fiber?.await()
    }
  }
}
