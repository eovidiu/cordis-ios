import Cordis
import Foundation

/// Runs the showcase: a root context that provides the dashboard, a loader
/// over the showcase catalog, and listeners that turn cordis's internal
/// events and logs into a timeline. Every change schedules a snapshot for
/// `onSnapshot`.
@CordisActor
public final class ShowcaseEngine {
  public let root = Context()
  public let loader: Loader
  public let dashboard = DashboardService()
  /// Receives a snapshot after every batch of changes, in revision order.
  public var onSnapshot: (@Sendable (ShowcaseSnapshot) -> Void)?

  /// A timeline line whose subject fiber is labelled when a snapshot is
  /// taken: a fiber's first events fire before the loader records which
  /// entry it runs.
  private struct Record {
    let event: TimelineEvent
    let subject: Fiber?
  }

  private var timeline: [Record] = []
  private var labels: [ObjectIdentifier: String] = [:]
  private var nextEventID = 0
  private var revision = 0
  private var refreshPending = false
  private var started = false
  private let timelineLimit = 400

  public init(store: any EntryStore) {
    loader = Loader(ctx: root, catalog: ShowcaseCatalog.make(), store: store)
  }

  /// Provides the dashboard, starts listening, and runs the stored entries.
  public func start() async throws {
    guard !started else { return }
    started = true
    dashboard.onChange = { [weak self] in self?.scheduleRefresh() }
    try root.provide(DashboardKey.self, dashboard)
    try root.logger.exporter(ClosureExporter(level: .info) { [weak self] message in
      self?.record(Self.kind(of: message.level), "\(message.name): \(message.text)")
    })
    try root.on(StatusEvent.self, options: EventOptions(global: true)) { [weak self] args in
      self?.record(.status, ": \(args.oldState) → \(args.fiber.state)", subject: args.fiber)
    }
    try root.on(ServiceEvent.self, options: EventOptions(global: true)) { [weak self] args in
      self?.record(.service, "service \"\(args.name)\" changed")
    }
    try root.on(PluginEvent.self, options: EventOptions(global: true)) { [weak self] fiber in
      self?.record(.plugin, fiber.uid == nil ? " fiber removed" : " fiber created", subject: fiber)
    }
    try await loader.start()
    scheduleRefresh()
  }

  /// Runs `operation` and reports what the system logged as errors meanwhile.
  public func run(_ operation: ShowcaseOperation) async -> OperationResult {
    record(.action, operation.description)
    let mark = nextEventID
    var thrown: String?
    do {
      try await perform(operation)
      await settle()
    } catch {
      thrown = String(describing: error)
    }
    let errors = timeline.filter { $0.event.id >= mark && $0.event.kind == .error }.map(\.event.text)
    scheduleRefresh()
    return OperationResult(errors: errors, thrown: thrown)
  }

  /// Runs a card button.
  public func trigger(_ action: CardAction) {
    action.run()
  }

  /// Waits until no fiber has a transition in flight, so a returned
  /// operation has also reloaded the plugins depending on what it changed.
  private func settle() async {
    func fibers(_ entries: [Entry]) -> [Fiber] {
      entries.flatMap { entry in [loader.fiber(for: entry.id)].compactMap { $0 } + fibers(entry.children ?? []) }
    }
    for _ in 0..<100 {
      guard let busy = fibers(loader.entries).first(where: { $0.inertia != nil }) else { return }
      _ = try? await busy.await()
    }
  }

  private func perform(_ operation: ShowcaseOperation) async throws {
    switch operation {
    case .setEnabled(let id, let enabled):
      try await loader.setDisabled(id: id, !enabled)
    case .updateConfig(let id, let config):
      try await loader.update(id: id, config: config)
    case .restart(let id):
      guard let fiber = loader.fiber(for: id) else { throw ShowcaseError.notRunning(id) }
      try await fiber.restart()
    case .remove(let id):
      try await loader.remove(id: id)
    case .add(let plugin, let config):
      guard let info = ShowcaseCatalog.info(plugin) else { throw ShowcaseError.unknownPlugin(plugin) }
      try await loader.add(Entry(id: freshID(for: plugin), plugin: plugin, config: config ?? info.defaultConfig))
    case .reset:
      try await loader.reconcile(ShowcaseCatalog.defaultEntries)
    }
  }

  private func freshID(for plugin: String) -> String {
    if loader.entry(plugin) == nil { return plugin }
    var suffix = 2
    while loader.entry("\(plugin)-\(suffix)") != nil { suffix += 1 }
    return "\(plugin)-\(suffix)"
  }

  // MARK: - timeline

  private static func kind(of level: LogLevel) -> TimelineEvent.Kind {
    switch level {
    case .error: .error
    case .warn: .warn
    case .info: .info
    default: .debug
    }
  }

  /// Appends a line; with a `subject`, `text` follows the subject's label.
  private func record(_ kind: TimelineEvent.Kind, _ text: String, subject: Fiber? = nil) {
    if let subject { _ = label(of: subject) }
    timeline.append(Record(event: TimelineEvent(id: nextEventID, date: Date(), kind: kind, text: text), subject: subject))
    nextEventID += 1
    if timeline.count > timelineLimit { timeline.removeFirst(timeline.count - timelineLimit) }
    scheduleRefresh()
  }

  private func resolvedTimeline() -> [TimelineEvent] {
    timeline.map { record in
      guard let subject = record.subject else { return record.event }
      let event = record.event
      return TimelineEvent(id: event.id, date: event.date, kind: event.kind, text: label(of: subject) + event.text)
    }
  }

  /// Entry id running `fiber` (remembered after the fiber is gone), else
  /// the fiber's plugin name.
  private func label(of fiber: Fiber) -> String {
    let key = ObjectIdentifier(fiber)
    if let known = labels[key] { return known }
    func search(_ entries: [Entry]) -> String? {
      for entry in entries {
        if loader.fiber(for: entry.id) === fiber { return entry.id }
        if let found = search(entry.children ?? []) { return found }
      }
      return nil
    }
    guard let id = search(loader.entries) else { return fiber.name }
    labels[key] = id
    return id
  }

  // MARK: - snapshots

  private func scheduleRefresh() {
    guard !refreshPending, onSnapshot != nil else { return }
    refreshPending = true
    Task { @CordisActor [weak self] in
      guard let self else { return }
      refreshPending = false
      onSnapshot?(snapshot())
    }
  }

  /// The current state of entries, cards, services and timeline.
  public func snapshot() -> ShowcaseSnapshot {
    revision += 1
    var rows: [EntryRow] = []
    func walk(_ entries: [Entry], parent: String?, depth: Int, parentDisabled: Bool) {
      for entry in entries {
        rows.append(row(for: entry, parent: parent, depth: depth, parentDisabled: parentDisabled))
        walk(entry.children ?? [], parent: entry.id, depth: depth + 1, parentDisabled: parentDisabled || entry.disabled)
      }
    }
    walk(loader.entries, parent: nil, depth: 0, parentDisabled: false)

    let order = Dictionary(rows.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
    let cards = dashboard.records
      .map { Card(id: $0.id, owner: label(of: $0.fiber), plugin: $0.fiber.name, content: $0.content) }
      .sorted { (order[$0.owner] ?? .max, $0.id) < (order[$1.owner] ?? .max, $1.id) }

    return ShowcaseSnapshot(
      revision: revision, entries: rows, cards: cards, services: services(rows), timeline: resolvedTimeline())
  }

  private func row(for entry: Entry, parent: String?, depth: Int, parentDisabled: Bool) -> EntryRow {
    let isGroup = entry.children != nil
    let info = isGroup ? nil : ShowcaseCatalog.info(entry.plugin)
    let fiber = loader.fiber(for: entry.id)
    if let fiber { labels[ObjectIdentifier(fiber)] = entry.id }
    let state: EntryState
    if entry.disabled {
      state = .disabled
    } else if let fiber {
      state = EntryState(fiber.state)
    } else if parentDisabled {
      state = .inactive
    } else if !isGroup && info == nil {
      state = .unknown
    } else {
      state = .disposed
    }
    let dependencies = (info?.injects ?? []).map { name in
      Dependency(name: name, available: fiber.map { ShowcaseCatalog.isAvailable(name, in: $0.ctx) })
    }
    var effects: [EffectLine] = []
    func flatten(_ metas: [EffectMeta], depth: Int) {
      for meta in metas {
        effects.append(EffectLine(label: meta.label, depth: depth))
        flatten(meta.children, depth: depth + 1)
      }
    }
    flatten(fiber?.getEffects() ?? [], depth: 0)
    let isolation = (entry.isolate ?? [:]).sorted { $0.key < $1.key }.map { name, spec in
      switch spec {
      case .local: "\(name) → private realm"
      case .shared(let realm): "\(name) → shared realm \"\(realm)\""
      }
    }
    return EntryRow(
      id: entry.id, plugin: isGroup ? "group" : entry.plugin, parent: parent, depth: depth, isGroup: isGroup,
      state: state, dependencies: dependencies, provides: info?.provides, isolation: isolation,
      config: entry.config.map(JSONText.pretty) ?? "", effects: effects,
      error: state == .failed ? fiber?.error.map { String(describing: $0) } : nil)
  }

  private func services(_ rows: [EntryRow]) -> [ServiceRow] {
    rows.compactMap { row in
      guard let name = row.provides else { return nil }
      let fiber = loader.fiber(for: row.id)
      let realm = fiber.map { realmLabel(name, in: $0.ctx) } ?? "—"
      let consumers = rows.filter { consumer in
        guard consumer.dependencies.contains(where: { $0.name == name }),
              let consumerFiber = loader.fiber(for: consumer.id) else { return false }
        return realmLabel(name, in: consumerFiber.ctx) == realm
      }.map(\.id)
      return ServiceRow(name: name, realm: realm, provider: row.id, state: row.state, consumers: consumers)
    }
  }
}

public enum ShowcaseError: Error, CustomStringConvertible {
  case notRunning(String)
  case unknownPlugin(String)

  public var description: String {
    switch self {
    case .notRunning(let id): "entry \"\(id)\" has no running fiber"
    case .unknownPlugin(let name): "plugin \"\(name)\" is not in the catalog"
    }
  }
}
