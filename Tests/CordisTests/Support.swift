import Foundation
import Testing
@testable import Cordis

struct TestError: Error, CustomStringConvertible, Equatable {
  let message: String
  init(_ message: String) { self.message = message }
  var description: String { message }
}

enum CustomEvent: EventKey {
  typealias Args = Void
  typealias Result = Never
  static let name = "custom-event"
}

enum WaterfallEvent: EventKey {
  typealias Args = Int
  typealias Result = Int
  static let name = "test/waterfall"
}

struct Payload: Sendable, Equatable {
  let bar: Int
}

enum Foo: ServiceKey {
  typealias Value = Payload
  static let name = "foo"
}

enum Bar: ServiceKey {
  typealias Value = Int
  static let name = "bar"
}

/// Lets tests restrict a listener to sessions with a matching flag
/// (cordis tests' `Filter`/`Session`).
enum FilterKey: InterceptKey {
  typealias Config = Bool
  static let name = "filter"
}

struct Session: EventScope {
  let flag: Bool
  func filter(_ hookContext: Context) -> Bool {
    guard let expected = hookContext.interceptConfig(FilterKey.self) else { return true }
    return expected == flag
  }
}

/// Counts calls and records arguments.
@CordisActor
final class Recorder<Value> {
  private(set) var calls: [Value] = []
  var count: Int { calls.count }
  func record(_ value: Value) { calls.append(value) }
  func reset() { calls.removeAll() }
}

/// A latch tests open explicitly; replaces cordis's fake timers.
@CordisActor
final class Gate {
  private var isOpen = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func wait() async {
    if isOpen { return }
    await withCheckedContinuation { waiters.append($0) }
  }

  func open() {
    isOpen = true
    for waiter in waiters { waiter.resume() }
    waiters.removeAll()
  }
}

/// Successive calls of `wait()` block on gate 0, 1, 2, …
@CordisActor
final class GateList {
  private var gates: [Gate] = []
  private(set) var calls = 0

  func gate(_ index: Int) -> Gate {
    while gates.count <= index { gates.append(Gate()) }
    return gates[index]
  }

  func wait() async {
    let gate = gate(calls)
    calls += 1
    await gate.wait()
  }
}

/// Lets queued work on `CordisActor` run (cordis tests' `await sleep()`).
func settle() async {
  try? await Task.sleep(for: .milliseconds(20))
}

@CordisActor
func errorCount(_ ctx: Context) -> Int {
  ctx.logger.buffer.filter { $0.level == .error }.count
}

/// `getHookSnapshot`: listener count per event name.
@CordisActor
func hookSnapshot(_ ctx: Context) -> [String: Int] {
  ctx.events.snapshot
}

/// A plugin that runs `body` (cordis tests' `mock.fn()` plugins).
func plugin<C: Decodable & Sendable>(
  _ config: C.Type,
  name: String? = nil,
  inject: [any ServiceKey.Type] = [],
  _ body: @escaping @CordisActor @Sendable (Context, C, EffectScope) async throws -> Void
) -> FunctionPlugin<C> {
  FunctionPlugin(name: name, inject: inject, apply: body)
}

func plugin(
  name: String? = nil,
  inject: [any ServiceKey.Type] = [],
  _ body: @escaping @CordisActor @Sendable (Context, NoConfig, EffectScope) async throws -> Void
) -> FunctionPlugin<NoConfig> {
  FunctionPlugin(name: name, inject: inject, apply: body)
}

/// Expects `body` to throw an error whose description contains `message`.
@CordisActor
func expectError(
  _ message: String,
  sourceLocation: SourceLocation = #_sourceLocation,
  _ body: () throws -> Void
) {
  do {
    try body()
    Issue.record("expected error containing \"\(message)\"", sourceLocation: sourceLocation)
  } catch {
    #expect(String(describing: error).contains(message), "\(error)", sourceLocation: sourceLocation)
  }
}
