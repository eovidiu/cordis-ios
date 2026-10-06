import Cordis
import Foundation
import Testing
@testable import ShowcaseKit

@CordisActor
private func startedEngine(_ entries: [Entry] = ShowcaseCatalog.defaultEntries) async throws -> ShowcaseEngine {
  let engine = ShowcaseEngine(store: InMemoryEntryStore(entries))
  try await engine.start()
  return engine
}

@CordisActor
private func states(_ engine: ShowcaseEngine) -> [String: EntryState] {
  Dictionary(uniqueKeysWithValues: engine.snapshot().entries.map { ($0.id, $0.state) })
}

@CordisActor
private func card(_ engine: ShowcaseEngine, owner: String) -> Card? {
  engine.snapshot().cards.first { $0.owner == owner }
}

@CordisActor
@discardableResult
private func run(_ engine: ShowcaseEngine, _ operation: ShowcaseOperation) async throws -> OperationResult {
  let result = await engine.run(operation)
  if let thrown = result.thrown { throw ShowcaseTestError(thrown) }
  return result
}

private struct ShowcaseTestError: Error, CustomStringConvertible {
  let description: String
  init(_ description: String) { self.description = description }
}

@Suite("ShowcaseEngine")
@CordisActor
struct ShowcaseEngineTests {
  @Test("default entries start in their documented states")
  func defaultStates() async throws {
    let engine = try await startedEngine()
    #expect(states(engine) == [
      "clock": .active, "clock-card": .active, "greeter": .active,
      "counter": .active, "counter-card": .active, "weather": .pending,
      "flaky": .failed, "theme": .active, "theme-card": .active,
      "night": .active, "night-theme": .active, "night-card": .active,
      "audit": .active,
    ])
    let weather = try #require(engine.snapshot().row("weather"))
    #expect(weather.dependencies.map(\.name) == ["dashboard", "network"])
    #expect(weather.dependencies.map(\.available) == [true, false])
    let flaky = try #require(engine.snapshot().row("flaky"))
    #expect(flaky.error?.contains("set \"fail\": false") == true)
    #expect(Set(engine.snapshot().cards.map(\.owner)) == [
      "clock-card", "greeter", "counter-card", "theme-card", "night-card", "audit",
    ])
  }

  @Test("disabling a service sends its consumer to pending and reverts the consumer's card")
  func disablingServiceReverts() async throws {
    let engine = try await startedEngine()
    #expect(card(engine, owner: "clock-card") != nil)
    try await run(engine, .setEnabled("clock", false))
    #expect(states(engine)["clock"] == .disabled)
    #expect(states(engine)["clock-card"] == .pending)
    #expect(card(engine, owner: "clock-card") == nil)
    #expect(engine.snapshot().row("clock-card")?.effects.isEmpty == true)

    try await run(engine, .setEnabled("clock", true))
    #expect(states(engine)["clock-card"] == .active)
    #expect(card(engine, owner: "clock-card") != nil)
  }

  @Test("a config update restarts the fiber; an invalid one is rejected and logged")
  func configUpdates() async throws {
    let engine = try await startedEngine()
    #expect(card(engine, owner: "greeter")?.value == "Hello, Ovidiu 👋")

    let applied = try await run(engine, .updateConfig("greeter", .object(["name": .string("World"), "emoji": .string("🌍")])))
    #expect(applied.errors.isEmpty)
    #expect(card(engine, owner: "greeter")?.value == "Hello, World 🌍")

    let rejected = try await run(engine, .updateConfig("greeter", .object(["name": .string("")])))
    #expect(rejected.errors.count == 1)
    #expect(rejected.errors.first?.contains("name must not be empty") == true)
    #expect(states(engine)["greeter"] == .active)
    #expect(card(engine, owner: "greeter")?.value == "Hello, World 🌍")
  }

  @Test("a rejected config is not persisted, so a relaunch still runs the last accepted one")
  func rejectedConfigNotPersisted() async throws {
    let store = InMemoryEntryStore(ShowcaseCatalog.defaultEntries)
    let engine = ShowcaseEngine(store: store)
    try await engine.start()
    let accepted: JSONValue = .object(["name": .string("World"), "emoji": .string("🌍")])
    try await run(engine, .updateConfig("greeter", accepted))
    #expect(store.entries.first { $0.id == "greeter" }?.config == accepted)

    let rejected = try await run(engine, .updateConfig("greeter", .object(["name": .string("")])))
    #expect(rejected.errors.count == 1)
    #expect(store.entries.first { $0.id == "greeter" }?.config == accepted)
    #expect(engine.snapshot().row("greeter")?.config == JSONText.pretty(accepted))

    let relaunched = ShowcaseEngine(store: store)
    try await relaunched.start()
    #expect(states(relaunched)["greeter"] == .active)
    #expect(card(relaunched, owner: "greeter")?.value == "Hello, World 🌍")
  }

  @Test("adding the missing service loads its waiting consumer")
  func addingService() async throws {
    let engine = try await startedEngine()
    #expect(card(engine, owner: "weather") == nil)
    try await run(engine, .add(plugin: "network", config: .object(["latency": .number(0.01)])))
    #expect(states(engine)["network"] == .active)
    #expect(states(engine)["weather"] == .active)
    #expect(card(engine, owner: "weather")?.title == "Weather in Bucharest")
  }

  @Test("added entries get unique ids")
  func uniqueIDs() async throws {
    let engine = try await startedEngine()
    try await run(engine, .add(plugin: "greeter", config: nil))
    try await run(engine, .add(plugin: "greeter", config: nil))
    let ids = engine.snapshot().entries.map(\.id)
    #expect(ids.filter { $0.hasPrefix("greeter") } == ["greeter", "greeter-2", "greeter-3"])
    #expect(card(engine, owner: "greeter-3")?.value == "Hello, World 👋")
  }

  @Test("a failed plugin recovers when its config is fixed")
  func failureRecovery() async throws {
    let engine = try await startedEngine()
    try await run(engine, .updateConfig("flaky", .object(["fail": .bool(false)])))
    #expect(states(engine)["flaky"] == .active)
    #expect(engine.snapshot().row("flaky")?.error == nil)
    #expect(card(engine, owner: "flaky") != nil)
  }

  @Test("isolated realms resolve the same service name to different providers")
  func isolation() async throws {
    let engine = try await startedEngine()
    #expect(card(engine, owner: "theme-card")?.value == "Day")
    #expect(card(engine, owner: "night-card")?.value == "Night")
    #expect(engine.snapshot().services.map(\.realm).sorted() == ["night:theme", "root", "root", "root"])

    try await run(engine, .setEnabled("night-theme", false))
    #expect(states(engine)["night-card"] == .pending)
    #expect(states(engine)["theme-card"] == .active)
    #expect(card(engine, owner: "theme-card")?.value == "Day")
  }

  @Test("disabling a group disposes its children")
  func groups() async throws {
    let engine = try await startedEngine()
    try await run(engine, .setEnabled("night", false))
    #expect(states(engine)["night"] == .disabled)
    #expect(states(engine)["night-theme"] == .inactive)
    #expect(states(engine)["night-card"] == .inactive)
    #expect(card(engine, owner: "night-card") == nil)
  }

  @Test("service state lives in the service instance; a restart resets it")
  func counterRestart() async throws {
    let engine = try await startedEngine()
    let increment = try #require(card(engine, owner: "counter-card")?.actions.first { $0.id == "increment" })
    engine.trigger(increment)
    engine.trigger(increment)
    #expect(card(engine, owner: "counter-card")?.value == "2")

    try await run(engine, .restart("counter"))
    #expect(states(engine)["counter-card"] == .active)
    #expect(card(engine, owner: "counter-card")?.value == "0")
  }

  @Test("the clock service emits ticks that its consumer renders")
  func ticks() async throws {
    var entries = ShowcaseCatalog.defaultEntries
    entries[0].config = .object(["interval": .number(0.1)])
    let engine = try await startedEngine(entries)
    try await Task.sleep(for: .milliseconds(450))
    let detail = try #require(card(engine, owner: "clock-card")?.detail)
    #expect(detail.hasSuffix("ticks from service \"clock\""))
    #expect(detail != "0 ticks from service \"clock\"")
  }

  @Test("the timeline records actions, status transitions and logged errors")
  func timeline() async throws {
    let engine = try await startedEngine()
    try await run(engine, .setEnabled("clock", false))
    let texts = engine.snapshot().timeline.map(\.text)
    #expect(texts.contains("disable clock"))
    #expect(texts.contains("clock-card: active → unloading"))
    #expect(texts.contains("clock-card: unloading → pending"))
    #expect(engine.snapshot().timeline.contains { $0.kind == .error && $0.text.contains("flaky") })
  }

  @Test("snapshots are published after changes")
  func publishing() async throws {
    let engine = ShowcaseEngine(store: InMemoryEntryStore(ShowcaseCatalog.defaultEntries))
    let received = Box<[Int]>([])
    engine.onSnapshot = { snapshot in Task { @CordisActor in received.value.append(snapshot.revision) } }
    try await engine.start()
    try await Task.sleep(for: .milliseconds(50))
    #expect(!received.value.isEmpty)
    #expect(received.value == received.value.sorted())
  }
}

@Suite("ShowcaseTour")
@CordisActor
struct ShowcaseTourTests {
  @Test("every tour step runs cleanly in order and ends back at the defaults")
  func tourRuns() async throws {
    let engine = try await startedEngine()
    let initial = states(engine)
    for step in TourStep.all {
      for operation in step.operations {
        let result = await engine.run(operation)
        #expect(result.thrown == nil, "step \(step.id): \(operation)")
      }
      if let expected = step.expectedStates {
        for (id, state) in expected {
          #expect(states(engine)[id] == state, "step \(step.id): \(id)")
        }
      }
    }
    #expect(states(engine).filter { $0.key != "network" } == initial)
  }
}

@Suite("ShowcaseJSONText")
struct JSONTextTests {
  @Test("typographic double quotes from the iOS keyboard parse as JSON; apostrophes in values survive")
  func smartQuotes() throws {
    #expect(try JSONText.parse("{“name”: “Ana’s”}") == .object(["name": .string("Ana’s")]))
  }

  @Test("blank text is no config; malformed text is a parse error")
  func blankAndMalformed() throws {
    #expect(try JSONText.parse("  \n") == nil)
    #expect(throws: JSONText.ParseError.self) { try JSONText.parse("{name: 1}") }
  }
}
