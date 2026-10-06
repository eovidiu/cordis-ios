import Testing
@testable import Cordis

struct FooBar: Codable, Sendable, Equatable {
  var foo: String
}

struct BarFoo: Codable, Sendable, Equatable {
  var bar: String
}

@CordisActor
final class ObjectPlugin: Plugin {
  typealias Config = BarFoo
  static var configs: [BarFoo] = []

  init(ctx: Context, config: BarFoo) {
    Self.configs.append(config)
  }

  func apply(_ scope: EffectScope) async throws {}
}

@CordisActor
final class Qux: Plugin {
  static var descriptions: [String] = []
  let ctx: Context

  init(ctx: Context, config: NoConfig) {
    self.ctx = ctx
  }

  func apply(_ scope: EffectScope) async throws {
    Self.descriptions.append(ctx.description)
  }
}

@CordisActor
final class StartStop: Plugin {
  static let start = Recorder<Void>()
  static let stop = Recorder<Void>()

  init(ctx: Context, config: NoConfig) {}

  func apply(_ scope: EffectScope) async throws {
    Self.start.record(())
    try scope.collect { Self.stop.record(()) }
  }
}

@Suite("PluginTests")
@CordisActor
struct PluginTests {
  @Test("apply functional plugin")
  func applyFunctionalPlugin() async throws {
    let root = Context()
    let calls = Recorder<FooBar>()
    try await root.plugin(plugin(FooBar.self) { _, config, _ in calls.record(config) }, config: FooBar(foo: "bar")).await()
    #expect(calls.calls == [FooBar(foo: "bar")])
  }

  @Test("apply object plugin")
  func applyObjectPlugin() async throws {
    let root = Context()
    ObjectPlugin.configs = []
    try await root.plugin(ObjectPlugin.self, config: BarFoo(bar: "foo")).await()
    #expect(ObjectPlugin.configs == [BarFoo(bar: "foo")])
  }

  @Test("apply invalid plugin")
  func applyInvalidPlugin() async throws {
    let root = Context()
    let fiber = try await root.plugin(plugin { _, _, _ in }).await()
    let ctx = fiber.ctx
    try await fiber.dispose()
    expectError("inactive context") { try ctx.plugin(plugin { _, _, _ in }) }
  }

  @Test("inactive context")
  func inactiveContext() async throws {
    let root = Context()
    let callback = Recorder<Void>()
    let errors = Recorder<String>()
    let fiber = try root.plugin(plugin { ctx, _, scope in
      try scope.collect {
        for body in [
          { _ = try ctx.plugin(plugin { _, _, _ in callback.record(()) }) },
          { _ = try ctx.effect(sync: { nil }) },
          { _ = try ctx.on(CustomEvent.self) { _ in } },
        ] as [@CordisActor () throws -> Void] {
          do { try body() } catch { errors.record(String(describing: error)) }
        }
      }
    })
    try await fiber.await()
    try await fiber.dispose()
    #expect(callback.count == 0)
    #expect(errors.calls.count == 3)
    #expect(errors.calls.allSatisfy { $0.contains("inactive context") })
  }

  @Test("context inspect")
  func contextInspect() async throws {
    let root = Context()
    let seen = Recorder<String>()
    #expect(root.description == "Context <root>")
    try await root.plugin(plugin { ctx, _, _ in seen.record(ctx.description) }).await()
    try await root.plugin(plugin(name: "foo") { ctx, _, _ in seen.record(ctx.description) }).await()
    try await root.plugin(plugin(name: "bar") { ctx, _, _ in seen.record(ctx.description) }).await()
    Qux.descriptions = []
    try await root.plugin(Qux.self).await()
    #expect(seen.calls == ["Context <root>", "Context <foo>", "Context <bar>"])
    #expect(Qux.descriptions == ["Context <Qux>"])
  }

  @Test("ctx.registry")
  func ctxRegistry() async throws {
    let root = Context()
    let first = plugin { _, _, _ in }
    try root.plugin(first)
    try root.plugin(first)
    try root.plugin(Qux.self)
    #expect(root.registry.size == 2)
    #expect(root.registry.runtimes.map(\.fiberList.count) == [2, 1])
    #expect(root.registry.has(first))
    #expect(root.registry.has(Qux.self))
    #expect(root.registry.get(Qux.self)?.name == "Qux")
  }

  @Test("nested plugins")
  func nestedPlugins() async throws {
    let root = Context()
    let callback = Recorder<Void>()
    try root.on(CustomEvent.self) { _ in callback.record(()) }
    let fiber = try await root.plugin(plugin { ctx, _, _ in
      try ctx.on(CustomEvent.self) { _ in callback.record(()) }
      try await ctx.plugin(plugin { ctx, _, _ in
        try ctx.on(CustomEvent.self) { _ in callback.record(()) }
        try await ctx.plugin(plugin { ctx, _, _ in
          try ctx.on(CustomEvent.self) { _ in callback.record(()) }
        }).await()
      }).await()
    }).await()

    // 4 handlers by now
    #expect(callback.count == 0)
    #expect(root.registry.size == 3)
    try root.emit(CustomEvent.self)
    #expect(callback.count == 4)

    // only 1 handler left
    callback.reset()
    try await fiber.dispose()
    #expect(root.registry.size == 0)
    try root.emit(CustomEvent.self)
    #expect(callback.count == 1)

    // subsequent calls should be noop
    callback.reset()
    try await fiber.dispose()
    #expect(root.registry.size == 0)
    try root.emit(CustomEvent.self)
    #expect(callback.count == 1)
  }

  @Test("compare snapshot")
  func compareSnapshot() async throws {
    let nested = plugin { ctx, _, _ in
      try ctx.on(CustomEvent.self) { _ in }
      try await ctx.plugin(plugin { ctx, _, _ in
        try ctx.on(CustomEvent.self) { _ in }
        try await ctx.plugin(plugin { ctx, _, _ in
          try ctx.on(CustomEvent.self) { _ in }
        }).await()
      }).await()
    }
    let root = Context()
    let before = hookSnapshot(root)
    try await root.plugin(nested).await()
    let after = hookSnapshot(root)
    await root.registry.delete(nested)
    await settle()
    #expect(before == hookSnapshot(root))
    try await root.plugin(nested).await()
    #expect(after == hookSnapshot(root))
  }

  @Test("root dispose")
  func rootDispose() async throws {
    let root = Context()
    let disposed = Recorder<Void>()
    let fiber = try root.plugin(plugin { _, _, scope in try scope.collect { disposed.record(()) } })
    #expect(root.fiber.uid == 0)
    #expect(fiber.uid == 1)
    #expect(disposed.count == 0)
    #expect(root.fiber.disposables.count == 1)
    try await fiber.await()
    try await root.fiber.dispose()
    #expect(root.fiber.uid == 0)
    #expect(fiber.uid == nil)
    #expect(disposed.count == 1)
    #expect(root.fiber.disposables.count == 0)
    try await root.fiber.dispose()
    #expect(root.fiber.uid == 0)
    #expect(fiber.uid == nil)
    #expect(disposed.count == 1)
    #expect(root.fiber.disposables.count == 0)
  }

  @Test("Service.init")
  func serviceInit() async throws {
    let root = Context()
    StartStop.start.reset()
    StartStop.stop.reset()
    let fiber = try await root.plugin(StartStop.self).await()
    #expect(StartStop.start.count == 1)
    #expect(StartStop.stop.count == 0)
    try await fiber.dispose()
    #expect(StartStop.start.count == 1)
    #expect(StartStop.stop.count == 1)
  }
}
