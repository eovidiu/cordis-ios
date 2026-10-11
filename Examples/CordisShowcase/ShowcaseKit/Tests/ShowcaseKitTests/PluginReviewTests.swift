import Cordis
import Foundation
import Testing
@testable import ShowcaseKit

/// Release review of the sample plugins: every catalog plugin can be added
/// from the UI and tells the user what it did, and no sequence of user
/// operations crashes the app or leaves the plugin tree inconsistent.
@Suite("ShowcasePluginReview")
@CordisActor
struct PluginReviewTests {
  /// Services each catalog plugin needs, as entries (fast configs).
  private static func providers(for info: PluginInfo) -> [Entry] {
    info.injects.compactMap { name -> Entry? in
      switch name {
      case "clock": Entry(id: "clock", plugin: "clock", config: .object(["interval": .number(0.1)]))
      case "counter": Entry(id: "counter", plugin: "counter")
      case "network": Entry(id: "network", plugin: "network", config: .object(["latency": .number(0.01)]))
      case "theme": Entry(id: "theme", plugin: "theme", config: .object(["name": .string("Day"), "tint": .string("orange")]))
      default: nil
      }
    }
  }

  @Test("every catalog plugin, added from the catalog, reports what it did", arguments: ShowcaseCatalog.plugins.map(\.name))
  func everyPluginReports(name: String) async throws {
    let info = try #require(ShowcaseCatalog.info(name))
    let engine = ShowcaseEngine(store: InMemoryEntryStore(Self.providers(for: info)))
    try await engine.start()
    let mark = engine.snapshot().timeline.last?.id ?? -1

    let result = await engine.run(.add(plugin: name, config: nil))
    #expect(result.thrown == nil)
    let snapshot = engine.snapshot()
    // the providers use other plugins' names as ids, so the new entry's id is the plugin name
    let row = try #require(snapshot.row(name))
    let card = snapshot.cards.contains { $0.owner == row.id }
    let logged = snapshot.timeline.contains { $0.id > mark && $0.kind == .info && $0.text.hasPrefix("\(row.id):") }
    switch row.state {
    case .active:
      #expect(card || logged, "\(name) is active but shows neither a card nor a log line")
    case .failed:
      // the store turns these errors into an alert
      #expect(!result.errors.isEmpty, "\(name) failed silently")
    default:
      Issue.record("\(name) ended \(row.state), missing \(row.missing)")
    }
  }

  @Test("a second provider of a service in the same realm fails visibly and leaves the first running", arguments: ["clock", "counter", "theme", "network"])
  func duplicateService(name: String) async throws {
    let engine = ShowcaseEngine(store: InMemoryEntryStore(ShowcaseCatalog.defaultEntries))
    try await engine.start()
    if name == "network" { _ = await engine.run(.add(plugin: "network", config: .object(["latency": .number(0.01)]))) }
    let result = await engine.run(.add(plugin: name, config: nil))
    #expect(result.thrown == nil)
    #expect(result.errors.contains { $0.contains("has been registered") })
    #expect(engine.snapshot().row(name)?.state == .active)
    #expect(engine.snapshot().row("\(name)-2")?.state == .failed)
  }

  @Test("random operation sequences keep the tree consistent", arguments: [1, 2, 3, 4, 5, 6, 7, 8] as [UInt64])
  func fuzz(seed: UInt64) async throws {
    var rng = SeededGenerator(seed: seed)
    let engine = ShowcaseEngine(store: InMemoryEntryStore(Self.fastDefaults))
    try await engine.start()
    for _ in 0..<120 {
      let operation = Self.randomOperation(engine.snapshot(), &rng)
      _ = await engine.run(operation)
      if Bool.random(using: &rng), let action = engine.snapshot().cards.flatMap(\.actions).randomElement(using: &rng) {
        engine.trigger(action)
      }
      try Self.checkInvariants(engine, after: operation)
    }
  }

  @Test("operations issued concurrently (fast taps) are applied one at a time")
  func concurrentOperations() async throws {
    var rng = SeededGenerator(seed: 42)
    let engine = ShowcaseEngine(store: InMemoryEntryStore(Self.fastDefaults))
    try await engine.start()
    for _ in 0..<15 {
      let operations = (0..<6).map { _ in Self.randomOperation(engine.snapshot(), &rng) }
      // like taps issued while earlier operations are still awaiting
      let tasks = operations.map { operation in Task { @CordisActor in _ = await engine.run(operation) } }
      for task in tasks { await task.value }
      try Self.checkInvariants(engine, after: .reset)
    }
  }

  // MARK: - helpers

  /// The default entries with fast timers and no network latency.
  static var fastDefaults: [Entry] {
    var entries = ShowcaseCatalog.defaultEntries
    entries[0].config = .object(["interval": .number(0.1)])
    return entries
  }

  static func randomOperation(_ snapshot: ShowcaseSnapshot, _ rng: inout SeededGenerator) -> ShowcaseOperation {
    let ids = snapshot.entries.map(\.id)
    let id = ids.randomElement(using: &rng) ?? "clock"
    let configs: [JSONValue?] = [
      nil, .object([:]), .object(["name": .string("")]), .object(["name": .string("Fuzz")]),
      .object(["interval": .number(0.01)]), .object(["interval": .number(0.2)]), .object(["latency": .number(0.01)]),
      .object(["latency": .number(99)]), .object(["tint": .string("nope")]), .object(["fail": .bool(false)]),
      .object(["fail": .bool(true)]), .string("not an object"), .array([]),
    ]
    switch Int.random(in: 0..<20, using: &rng) {
    case 0..<6: return .setEnabled(id, Bool.random(using: &rng))
    case 6..<10: return .updateConfig(id, configs.randomElement(using: &rng)!)
    case 10..<12: return .restart(id)
    case 12..<14: return .remove(id)
    case 14..<19:
      let plugin = ShowcaseCatalog.plugins.randomElement(using: &rng)!.name
      return .add(plugin: plugin, config: plugin == "network" ? .object(["latency": .number(0.01)]) : nil)
    default: return .reset
    }
  }

  static func checkInvariants(_ engine: ShowcaseEngine, after operation: ShowcaseOperation) throws {
    let snapshot = engine.snapshot()
    // ids are unique
    #expect(Set(snapshot.entries.map(\.id)).count == snapshot.entries.count, "duplicate ids after \(operation)")
    // each running entry has exactly one live fiber, and no orphan fibers exist
    let live = engine.root.registry.runtimes.flatMap(\.fiberList).filter { $0.uid != nil }
    let owned = snapshot.entries.compactMap { engine.loader.fiber(for: $0.id) }
    #expect(live.count == owned.count, "\(live.count) live fibers for \(owned.count) entries after \(operation)")
    // nothing is mid-transition once an operation returned
    #expect(!owned.contains { $0.inertia != nil }, "transition still in flight after \(operation)")
    // every card belongs to an active entry
    for card in snapshot.cards {
      #expect(snapshot.row(card.owner)?.state == .active, "card of \(card.owner) shown while \(snapshot.row(card.owner)?.state.rawValue ?? "absent") after \(operation)")
    }
  }
}

/// Deterministic generator so a failing fuzz run can be replayed.
struct SeededGenerator: RandomNumberGenerator {
  private var state: UInt64
  init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 | 1 }
  mutating func next() -> UInt64 {
    state ^= state << 13
    state ^= state >> 7
    state ^= state << 17
    return state
  }
}
