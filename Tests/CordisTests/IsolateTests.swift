import Testing
@testable import Cordis

@CordisActor
final class IsolatedEmitter: ServicePlugin {
  typealias Key = IsolatedEmitterKey
  let ctx: Context

  init(ctx: Context, config: NoConfig) {
    self.ctx = ctx
  }

  func setup(_ scope: EffectScope) async throws {
    try ctx.emit(scope: eventScope, CustomEvent.self)
  }
}

enum IsolatedEmitterKey: ServiceKey {
  typealias Value = IsolatedEmitter
  static let name = "foo"
}

@Suite("IsolateTests")
@CordisActor
struct IsolateTests {
  private func consumer(_ callback: Recorder<Void>, _ disposed: Recorder<Void>) -> FunctionPlugin<NoConfig> {
    plugin(inject: [Foo.self]) { _, _, scope in
      callback.record(())
      try scope.collect { disposed.record(()) }
    }
  }

  @Test("isolated context")
  func isolatedContext() async throws {
    let root = Context()
    let callback = Recorder<Void>()
    let disposed = Recorder<Void>()
    let plugin = consumer(callback, disposed)

    try await root.plugin(plugin).await()
    let ctx1 = root.isolate(Foo.self)
    let fiber1 = try await ctx1.plugin(plugin).await()
    let ctx2 = root.isolate(Foo.self)
    try await ctx2.plugin(plugin).await()

    let dispose0 = try root.provide(Foo.self, Payload(bar: 100))
    #expect(root.get(Foo.self, strict: false) == Payload(bar: 100))
    #expect(ctx1.get(Foo.self, strict: false) == nil)
    #expect(ctx2.get(Foo.self, strict: false) == nil)
    await settle()
    #expect(callback.count == 1)
    #expect(disposed.count == 0)

    try ctx1.provide(Foo.self, Payload(bar: 200))
    #expect(root.get(Foo.self, strict: false) == Payload(bar: 100))
    #expect(ctx1.get(Foo.self, strict: false) == Payload(bar: 200))
    #expect(ctx2.get(Foo.self, strict: false) == nil)
    await settle()
    #expect(callback.count == 2)
    #expect(disposed.count == 0)

    try await dispose0.dispose()
    #expect(root.get(Foo.self, strict: false) == nil)
    #expect(ctx1.get(Foo.self, strict: false) == Payload(bar: 200))
    #expect(ctx2.get(Foo.self, strict: false) == nil)
    expectError("cannot get property \"foo\" without inject") { _ = try root[Foo.self] }
    #expect(fiber1.state == .active)
    #expect(try fiber1.ctx[Foo.self] == Payload(bar: 200))
    await settle()
    #expect(callback.count == 2)
    #expect(disposed.count == 1)

    try ctx2.provide(Foo.self, Payload(bar: 300))
    #expect(root.get(Foo.self, strict: false) == nil)
    #expect(ctx1.get(Foo.self, strict: false) == Payload(bar: 200))
    #expect(ctx2.get(Foo.self, strict: false) == Payload(bar: 300))
    await settle()
    #expect(callback.count == 3)
    #expect(disposed.count == 1)
  }

  @Test("shared label")
  func sharedLabel() async throws {
    let root = Context()
    let callback = Recorder<Void>()
    let disposed = Recorder<Void>()
    let plugin = consumer(callback, disposed)

    let label = root.makeRealm(name: "test")
    try await root.plugin(plugin).await()
    let ctx1 = root.isolate(Foo.self, realm: label)
    try await ctx1.plugin(plugin).await()
    let ctx2 = root.isolate(Foo.self, realm: label)
    try await ctx2.plugin(plugin).await()
    await settle()
    #expect(callback.count == 0)

    try root.provide(Foo.self, Payload(bar: 100))
    #expect(root.get(Foo.self, strict: false) == Payload(bar: 100))
    #expect(ctx1.get(Foo.self, strict: false) == nil)
    #expect(ctx2.get(Foo.self, strict: false) == nil)
    await settle()
    #expect(callback.count == 1)
    #expect(disposed.count == 0)

    let dispose12 = try ctx1.provide(Foo.self, Payload(bar: 200))
    #expect(root.get(Foo.self, strict: false) == Payload(bar: 100))
    #expect(ctx1.get(Foo.self, strict: false) == Payload(bar: 200))
    #expect(ctx2.get(Foo.self, strict: false) == Payload(bar: 200))
    await settle()
    #expect(callback.count == 3)
    #expect(disposed.count == 0)

    try await dispose12.dispose()
    #expect(root.get(Foo.self, strict: false) == Payload(bar: 100))
    #expect(ctx1.get(Foo.self, strict: false) == nil)
    #expect(ctx2.get(Foo.self, strict: false) == nil)
    await settle()
    #expect(callback.count == 3)
    #expect(disposed.count == 2)
  }

  @Test("isolated event")
  func isolatedEvent() async throws {
    let root = Context()
    let ctx = root.isolate(IsolatedEmitterKey.self)
    let outer = Recorder<Void>()
    let inner = Recorder<Void>()
    try root.on(CustomEvent.self) { _ in outer.record(()) }
    try ctx.on(CustomEvent.self) { _ in inner.record(()) }
    try await ctx.plugin(IsolatedEmitter.self).await()
    #expect(outer.count == 0)
    #expect(inner.count == 1)
  }
}
