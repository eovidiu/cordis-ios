import Testing
@testable import Cordis

@CordisActor
final class PendingFoo: ServicePlugin {
  typealias Key = PendingFooKey
  let ctx: Context

  init(ctx: Context, config: NoConfig) {
    self.ctx = ctx
  }

  func setup(_ scope: EffectScope) async throws {
    await withCheckedContinuation { continuation in
      _ = try? ctx.once(CustomEvent.self) { _ in continuation.resume() }
    }
  }
}

enum PendingFooKey: ServiceKey {
  typealias Value = PendingFoo
  static let name = "foo"
}

@CordisActor
final class SelfInjecting: ServicePlugin {
  typealias Key = SelfInjectingKey
  let ctx: Context

  init(ctx: Context, config: NoConfig) {
    self.ctx = ctx
  }

  func setup(_ scope: EffectScope) async throws {
    try ctx.inject([SelfInjectingKey.self]) { _, _ in }
  }
}

enum SelfInjectingKey: ServiceKey {
  typealias Value = SelfInjecting
  static let name = "test"
}

@CordisActor
let multiSetups = Recorder<String>()

@CordisActor
final class MultiFoo: ServicePlugin {
  typealias Key = MultiFooKey
  nonisolated static var inject: [any ServiceKey.Type] { [MultiQuxKey.self] }
  let ctx: Context
  init(ctx: Context, config: NoConfig) { self.ctx = ctx }
  func setup(_ scope: EffectScope) async throws { multiSetups.record("foo") }
}

@CordisActor
final class MultiBar: ServicePlugin {
  typealias Key = MultiBarKey
  nonisolated static var inject: [any ServiceKey.Type] { [MultiFooKey.self, MultiQuxKey.self] }
  let ctx: Context
  init(ctx: Context, config: NoConfig) { self.ctx = ctx }
  func setup(_ scope: EffectScope) async throws { multiSetups.record("bar") }
}

@CordisActor
final class MultiQux: ServicePlugin {
  typealias Key = MultiQuxKey
  let ctx: Context
  init(ctx: Context, config: NoConfig) { self.ctx = ctx }
  func setup(_ scope: EffectScope) async throws { multiSetups.record("qux") }
}

enum MultiFooKey: ServiceKey {
  typealias Value = MultiFoo
  static let name = "foo"
}

enum MultiBarKey: ServiceKey {
  typealias Value = MultiBar
  static let name = "bar"
}

enum MultiQuxKey: ServiceKey {
  typealias Value = MultiQux
  static let name = "qux"
}

@Suite("ServiceTests")
@CordisActor
struct ServiceTests {
  @Test("pending inject")
  func pendingInject() async throws {
    let root = Context()
    let callback = Recorder<Void>()
    try root.inject([PendingFooKey.self]) { _, _ in callback.record(()) }
    #expect(callback.count == 0)

    // inject should be blocked by `setup`
    try root.plugin(PendingFoo.self)
    await settle()
    #expect(callback.count == 0)

    try root.emit(CustomEvent.self)
    await settle()
    #expect(callback.count == 1)
  }

  @Test("compare snapshot")
  func compareSnapshot() async throws {
    let root = Context()
    let before = hookSnapshot(root)
    try await root.plugin(SelfInjecting.self).await()
    let after = hookSnapshot(root)
    await root.registry.delete(SelfInjecting.self)
    await settle()
    #expect(before == hookSnapshot(root))
    try root.plugin(SelfInjecting.self)
    #expect(after == hookSnapshot(root))
    #expect(root.registry.size == 1)
  }

  @Test("multiple injects")
  func multipleInjects() async throws {
    let root = Context()
    multiSetups.reset()
    try await root.plugin(MultiFoo.self).await()
    try await root.plugin(MultiBar.self).await()
    try await root.plugin(MultiQux.self).await()
    await settle()
    #expect(multiSetups.calls.sorted() == ["bar", "foo", "qux"])
    #expect(root.registry.runtimes.allSatisfy { $0.fiberList.allSatisfy { $0.state == .active } })
  }
}
