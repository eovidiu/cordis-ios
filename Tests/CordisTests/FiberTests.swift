import Testing
@testable import Cordis

@CordisActor
final class FooService: ServicePlugin {
  typealias Key = FooServiceKey
  let ctx: Context

  init(ctx: Context, config: NoConfig) {
    self.ctx = ctx
  }
}

enum FooServiceKey: ServiceKey {
  typealias Value = FooService
  static let name = "foo"
}

@CordisActor
final class ProviderService: ServicePlugin {
  struct Config: Codable, Sendable {
    var value: Int
  }

  typealias Key = ProviderKey
  let ctx: Context
  let value: Int

  init(ctx: Context, config: Config) {
    self.ctx = ctx
    self.value = config.value
  }
}

enum ProviderKey: ServiceKey {
  typealias Value = ProviderService
  static let name = "provider"
}

struct FooFlag: Codable, Sendable {
  var foo: Bool?
}

struct Message: Codable, Sendable, Equatable {
  var msg: String
}

struct Mode: Codable, Sendable, Equatable {
  var mode: String
}

struct Applied: Equatable {
  let value: Int
  let mode: String
}

@Suite("FiberTests")
@CordisActor
struct FiberTests {
  @Test("inertia lock 1")
  func inertiaLock1() async throws {
    let root = Context()
    let states = Recorder<FiberState>()
    let consumerUID = Box<Int?>(nil)
    try root.on(StatusEvent.self) { args in
      if args.fiber.uid == consumerUID.value { states.record(args.fiber.state) }
    }
    consumerUID.value = root.registry.counter + 1
    let provider = try root.provide(Foo.self, Payload(bar: 1))
    let loads = GateList()
    let unloads = GateList()
    let fiber = try root.inject([Foo.self]) { _, scope in
      await loads.wait()
      try scope.collect { await unloads.wait() }
    }
    await settle()
    #expect(fiber.state == .loading)
    let disposing = Task { try await provider.dispose() }
    await settle()
    #expect(fiber.state == .loading)
    loads.gate(0).open()
    await settle()
    #expect(fiber.state == .unloading)
    try root.provide(Foo.self, Payload(bar: 1))
    unloads.gate(0).open()
    await settle()
    #expect(fiber.state == .loading)
    loads.gate(1).open()
    await settle()
    #expect(fiber.state == .active)
    try await disposing.value
    #expect(states.calls == [.loading, .unloading, .loading, .active])
  }

  @Test("inertia lock 2")
  func inertiaLock2() async throws {
    let root = Context()
    let provider = try root.provide(Foo.self, Payload(bar: 1))
    let loads = GateList()
    let fiber = try root.inject([Foo.self]) { _, scope in
      await loads.wait()
      try scope.collect {}
    }
    await settle()
    #expect(fiber.state == .loading)
    let disposing = Task { try await provider.dispose() }
    await settle()
    #expect(fiber.state == .loading)
    try root.provide(Foo.self, Payload(bar: 2))
    loads.gate(0).open()
    await settle()
    #expect(fiber.state == .active)
    try await disposing.value
  }

  @Test("inertia lock 3")
  func inertiaLock3() async throws {
    let root = Context()
    let provider = try await root.plugin(FooService.self).await()
    let loads = GateList()
    let unloads = GateList()
    let fiber = try root.inject([FooServiceKey.self]) { _, scope in
      await loads.wait()
      try scope.collect { await unloads.wait() }
    }
    await settle()
    #expect(fiber.state == .loading)
    loads.gate(0).open()
    await settle()
    #expect(fiber.state == .active)
    let disposing = Task { try await provider.dispose() }
    await settle()
    unloads.gate(0).open()
    try await disposing.value
    #expect(fiber.state == .pending)
  }

  @Test("plugin error")
  func pluginError() async throws {
    let root = Context()
    let callback = Recorder<Void>()
    let apply = plugin(FooFlag.self) { ctx, config, _ in
      try ctx.on(CustomEvent.self) { _ in callback.record(()) }
      if config.foo != true { throw TestError("plugin error") }
    }
    let fiber1 = try root.plugin(apply)
    let fiber2 = try root.plugin(apply, config: FooFlag(foo: true))
    await settle()
    #expect(fiber1.state == .failed)
    #expect(fiber2.state == .active)
    #expect(errorCount(root) == 1)

    try root.emit(CustomEvent.self)
    #expect(callback.count == 1)
  }

  @Test("failed fiber does not re-enter on dependency refresh")
  func failedFiberDoesNotReenter() async throws {
    let root = Context()
    let applied = Recorder<Void>()
    let provider = try root.provide(Foo.self, Payload(bar: 1))
    let fiber = try root.inject([Foo.self]) { _, _ in
      applied.record(())
      throw TestError("boom")
    }
    await settle()
    #expect(fiber.state == .failed)
    try await provider.dispose()
    try root.provide(Foo.self, Payload(bar: 2))
    await settle()
    #expect(applied.count == 1)
    #expect(fiber.state == .failed)
  }

  @Test("update recovers a failed fiber")
  func updateRecoversFailedFiber() async throws {
    let root = Context()
    let applied = Recorder<Void>()
    try root.provide(Foo.self, Payload(bar: 1))
    let fiber = try root.inject([Foo.self]) { _, _ in
      applied.record(())
      if applied.count == 1 { throw TestError("boom") }
    }
    await settle()
    #expect(fiber.state == .failed)
    #expect(errorCount(root) == 1)
    try await fiber.update(nil)
    try await fiber.await()
    #expect(applied.count == 2)
    #expect(fiber.state == .active)
  }

  @Test("update surfaces a failed reload to its caller")
  func updateSurfacesFailedReload() async throws {
    let root = Context()
    let applied = Recorder<Void>()
    let fiber = try root.plugin(plugin { _, _, _ in
      applied.record(())
      if applied.count == 2 { throw TestError("boom") }
    })
    try await fiber.await()
    await #expect(throws: TestError("boom")) { try await fiber.update(NoConfig()) }
    #expect(fiber.state == .failed)
  }

  // the fiber reports the failure itself, so a caller that never asks for the
  // result must not be punished with an unhandled error
  @Test("update does not leak a dropped failure")
  func updateDoesNotLeakDroppedFailure() async throws {
    let root = Context()
    let applied = Recorder<Void>()
    let fiber = try root.plugin(plugin { _, _, _ in
      applied.record(())
      if applied.count == 2 { throw TestError("boom") }
    })
    try await fiber.await()
    Task { try await fiber.update(NoConfig()) }
    await settle()
    #expect(fiber.state == .failed)
  }

  @Test("dispose error")
  func disposeError() async throws {
    let root = Context()
    let disposed = Recorder<Void>()
    let fiber = try await root.plugin(plugin { _, _, scope in
      try scope.collect {
        disposed.record(())
        throw TestError("test")
      }
    }).await()
    #expect(disposed.count == 0)
    try await fiber.dispose()
    await settle()
    #expect(disposed.count == 1)
    #expect(errorCount(root) == 1)
  }

  @Test("update config on wrapped fiber")
  func updateConfigOnWrappedFiber() async throws {
    let root = Context()
    let configs = Recorder<Message>()
    let fiber = try root.plugin(plugin(Message.self) { _, config, _ in configs.record(config) }, config: Message(msg: "hello"))
    try await fiber.await()
    #expect(configs.calls == [Message(msg: "hello")])

    try await fiber.update(Message(msg: "world"))
    try await fiber.await()
    #expect(configs.calls == [Message(msg: "hello"), Message(msg: "world")])

    try await fiber.update(JSONValue.object(["msg": .string("!!!")]))
    try await fiber.await()
    #expect(configs.calls == [Message(msg: "hello"), Message(msg: "world"), Message(msg: "!!!")])
  }

  @Test("restart wrapped fiber")
  func restartWrappedFiber() async throws {
    let root = Context()
    let applied = Recorder<Void>()
    let fiber = try root.plugin(plugin { _, _, _ in applied.record(()) })
    try await fiber.await()
    try await fiber.restart()
    #expect(applied.count == 2)
    #expect(fiber.state == .active)
    #expect(fiber.inertia == nil)
  }

  @Test("update config while injected service reloads")
  func updateConfigWhileInjectedServiceReloads() async throws {
    let applied = Recorder<Applied>()
    let consumerPlugin = plugin(Mode.self, inject: [ProviderKey.self]) { ctx, config, _ in
      applied.record(Applied(value: try ctx[ProviderKey.self].value, mode: config.mode))
    }
    let root = Context()
    let provider = try root.plugin(ProviderService.self, config: .init(value: 1))
    let consumer = try root.plugin(consumerPlugin, config: Mode(mode: "old"))
    try await provider.await()
    try await consumer.await()

    async let providerUpdate: Void = provider.update(ProviderService.Config(value: 2))
    async let consumerUpdate: Void = consumer.update(Mode(mode: "new"))
    try await providerUpdate
    try await consumerUpdate
    try await provider.await()
    try await consumer.await()

    #expect(applied.calls == [Applied(value: 1, mode: "old"), Applied(value: 2, mode: "new")])
    #expect((consumer.config as? Mode) == Mode(mode: "new"))
    #expect(consumer.state == .active)
    #expect(consumer.inertia == nil)
  }
}

@Suite("FiberMissingInjectionTests")
@CordisActor
struct FiberMissingInjectionTests {
  @Test("missingInjections lists the injected services that are not provided")
  func missingInjections() async throws {
    let root = Context()
    try root.provide(Foo.self, Payload(bar: 1))
    let fiber = try root.inject([Foo.self, Bar.self]) { _, _ in }
    await settle()
    #expect(fiber.state == .pending)
    #expect(fiber.missingInjections == ["bar"])
    let bar = try root.provide(Bar.self, 2)
    try await fiber.await()
    #expect(fiber.state == .active)
    #expect(fiber.missingInjections == [])
    try await bar.dispose()
    await settle()
    #expect(fiber.missingInjections == ["bar"])
  }
}
