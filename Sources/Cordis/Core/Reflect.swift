/// One provided service value.
@CordisActor
public final class Impl {
  public let name: String
  public internal(set) var value: (any Sendable)?
  /// The fiber that provides the service.
  public let fiber: Fiber
  /// The context the service was provided from (decides its realm).
  public let ctx: Context
  let check: (@CordisActor () -> Bool)?

  init(name: String, value: (any Sendable)?, fiber: Fiber, ctx: Context, check: (@CordisActor () -> Bool)?) {
    self.name = name
    self.value = value
    self.fiber = fiber
    self.ctx = ctx
    self.check = check
  }
}

/// Service storage and change propagation (port of cordis `reflect.ts`;
/// accessors and mixins are not ported).
@CordisActor
public final class ReflectService {
  private unowned let root: Context
  /// Every name ever provided.
  public private(set) var props: Set<String> = []
  /// Provided services by realm.
  public private(set) var store: [Realm: Impl] = [:]

  init(root: Context) {
    self.root = root
  }

  func getImpl(_ name: String, in ctx: Context, strict: Bool) -> Impl? {
    guard let realm = ctx.isolateTable.lookup(name), let impl = store[realm] else { return nil }
    if strict && impl.fiber.state != .active { return nil }
    return impl
  }

  func set(_ name: String, _ value: (any Sendable)?, in ctx: Context) throws {
    guard let realm = ctx.isolateTable.lookup(name), let impl = store[realm] else {
      throw CordisError.setWithoutProvide(name)
    }
    if impl.fiber !== ctx.fiber {
      throw CordisError.setInOtherFiber(name)
    }
    impl.value = value
  }

  func provide(
    _ name: String,
    _ value: (any Sendable)?,
    check: (@CordisActor () -> Bool)?,
    in ctx: Context
  ) throws -> EffectHandle {
    try ctx.fiber.effect("ctx.provide(\"\(name)\")", sync: { [self] in
      props.insert(name)
      if root.isolateTable.own[name] == nil {
        root.isolateTable.own[name] = root.makeRealm(name: name)
      }
      let realm = ctx.isolateTable.lookup(name)!
      if let existing = store[realm] {
        throw CordisError.duplicateService(name, at: existing.fiber.name)
      }
      let fiber = ctx.fiber
      let impl = Impl(name: name, value: value, fiber: fiber, ctx: ctx, check: check)
      store[realm] = impl
      fiber.store?[name] = impl
      if fiber.state == .active {
        notify([name], from: ctx)
      }
      return { [self] in
        if store[realm] === impl { store[realm] = nil }
        let fibers = notify([name], from: ctx)
        for fiber in fibers {
          _ = try? await fiber.await()
        }
        // ensure self access before dependencies cleanup
        if fiber.store?[name] === impl { fiber.store?[name] = nil }
      }
    })
  }

  /// Re-checks every fiber that injects one of `names` in the same realm as
  /// `source` and refreshes it; emits `internal/service` to listeners in
  /// that realm. Returns the refreshed fibers.
  @discardableResult
  func notify(_ names: [String], from source: Context) -> [Fiber] {
    var fibers: [Fiber] = []
    for runtime in root.registry.runtimes {
      for fiber in runtime.fibers.values {
        var hasUpdate = false
        for name in names {
          guard fiber.inject.keys.contains(name) else { continue }
          guard fiber.ctx.isolateTable.lookup(name) == source.isolateTable.lookup(name) else { continue }
          hasUpdate = true
          fiber.checkImpl(name)
        }
        if !hasUpdate { continue }
        fiber.refresh()
        fibers.append(fiber)
      }
    }
    for name in names {
      let value = getImpl(name, in: source, strict: false)?.value
      source.emitInternal(ServiceEvent.self, (name: name, value: value), scope: IsolationScope(ctx: source, name: name))
    }
    return fibers
  }
}

/// Event scope that only reaches listeners whose context resolves `name` in
/// the same realm as `ctx` (cordis `Service[symbols.filter]`).
public struct IsolationScope: EventScope {
  public let ctx: Context
  public let name: String

  public init(ctx: Context, name: String) {
    self.ctx = ctx
    self.name = name
  }

  public func filter(_ hookContext: Context) -> Bool {
    hookContext.isolateTable.lookup(name) == ctx.isolateTable.lookup(name)
  }
}
