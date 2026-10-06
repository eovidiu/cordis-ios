import Testing
@testable import Cordis

@CordisActor
final class LeakProbe: Plugin {
  static weak var lastInstance: LeakProbe?
  let ctx: Context

  init(ctx: Context, config: NoConfig) {
    self.ctx = ctx
    Self.lastInstance = self
  }

  func apply(_ scope: EffectScope) async throws {
    try ctx.on(CustomEvent.self) { [unowned self] _ in _ = self.ctx }
    try scope.collect { [self] in _ = self.ctx }
  }
}

@CordisActor
final class LoaderLeakProbe: Plugin {
  init(ctx: Context, config: NoConfig) {}
  func apply(_ scope: EffectScope) async throws {}
}

@Suite("FiberLeakTests")
@CordisActor
struct FiberLeakTests {
  @Test("a disposed plugin frees its fiber, context and instance")
  func disposedPluginIsFreed() async throws {
    let root = Context()
    weak var weakFiber: Fiber?
    weak var weakContext: Context?
    do {
      let fiber = try await root.plugin(LeakProbe.self).await()
      weakFiber = fiber
      weakContext = fiber.ctx
      #expect(LeakProbe.lastInstance != nil)
      try await fiber.dispose()
    }
    await settle()
    #expect(weakFiber == nil)
    #expect(weakContext == nil)
    #expect(LeakProbe.lastInstance == nil)
  }

  @Test("toggling through the loader does not accumulate fibers")
  func loaderToggleDoesNotLeak() async throws {
    var catalog = PluginCatalog()
    catalog.register(LoaderLeakProbe.self, as: "probe")
    let loader = Loader(ctx: Context(), catalog: catalog, store: InMemoryEntryStore([Entry(id: "p", plugin: "probe")]))
    try await loader.start()
    var weakFibers: [WeakFiber] = []
    for _ in 0..<50 {
      weakFibers.append(WeakFiber(loader.fiber(for: "p")))
      try await loader.setDisabled(id: "p", true)
      try await loader.setDisabled(id: "p", false)
    }
    await settle()
    #expect(weakFibers.allSatisfy { $0.fiber == nil })
    #expect(loader.fiber(for: "p")?.state == .active)
  }

  @Test("a held fiber still reports an inactive context after disposal")
  func heldFiberAfterDisposal() async throws {
    let root = Context()
    try root.provide(Foo.self, Payload(bar: 1))
    let fiber = try await root.inject([Foo.self]) { _, _ in }.await()
    try await fiber.dispose()
    await settle()
    expectError("cannot get required service \"foo\" in inactive context") { _ = try fiber.ctx[Foo.self] }
    #expect(fiber.ctx.fiber === fiber)
  }
}

@CordisActor
final class WeakFiber {
  weak var fiber: Fiber?
  init(_ fiber: Fiber?) { self.fiber = fiber }
}
