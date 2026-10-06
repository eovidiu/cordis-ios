/// Options for `ctx.on`.
public struct EventOptions: Sendable {
  /// Run before listeners registered earlier.
  public var prepend: Bool
  /// Ignore dispatch scopes; for `UpdateEvent`, listen to every fiber's
  /// updates instead of only this context's fiber.
  public var global: Bool

  public init(prepend: Bool = false, global: Bool = false) {
    self.prepend = prepend
    self.global = global
  }
}

/// Restricts which listeners a dispatch reaches (cordis `thisArg[Context.filter]`).
public protocol EventScope: Sendable {
  @CordisActor func filter(_ hookContext: Context) -> Bool
}

/// A plugin was created or disposed (`internal/plugin`).
public enum PluginEvent: EventKey {
  public typealias Args = Fiber
  public typealias Result = Never
  public static let name = "internal/plugin"
}

/// A fiber changed state (`internal/status`); `fiber.state` is the new one.
public enum StatusEvent: EventKey {
  public typealias Args = (fiber: Fiber, oldState: FiberState)
  public typealias Result = Never
  public static let name = "internal/status"
}

/// A service was provided, withdrawn, or its provider changed state
/// (`internal/service`). Only listeners in the service's realm receive it.
public enum ServiceEvent: EventKey {
  public typealias Args = (name: String, value: (any Sendable)?)
  public typealias Result = Never
  public static let name = "internal/service"
}

/// `fiber.update(config)` waterfall (`internal/update`). A non-global
/// listener only sees updates of its own fiber; a listener that does not
/// call `next` vetoes the update.
public enum UpdateEvent: EventKey {
  public typealias Args = (fiber: Fiber, config: (any Sendable)?, noSave: Bool)
  public typealias Result = Void
  public static let name = "internal/update"
}

typealias ErasedNext = @CordisActor () async throws -> any Sendable
typealias ErasedWaterfall = @CordisActor (any Sendable, @escaping ErasedNext) async throws -> any Sendable

enum HookCallback {
  case sync(@CordisActor (any Sendable) throws -> (any Sendable)?)
  case async(@CordisActor (any Sendable) async throws -> (any Sendable)?)
  case waterfall(ErasedWaterfall)
}

struct Hook {
  let id: UInt64
  let ctx: Context
  let global: Bool
  let callback: HookCallback
}

/// Runs waterfall callbacks as an onion: each receives a `next` that runs
/// the rest. `guarded` makes each `next` single-use (cordis `waterfall`);
/// fiber update hooks are unguarded, as in cordis.
@CordisActor
private final class Onion {
  let callbacks: [ErasedWaterfall]
  let args: any Sendable
  let guarded: Bool
  let terminal: ErasedNext
  var index = 0

  init(callbacks: [ErasedWaterfall], args: any Sendable, guarded: Bool, terminal: @escaping ErasedNext) {
    self.callbacks = callbacks
    self.args = args
    self.guarded = guarded
    self.terminal = terminal
  }

  func run() async throws -> any Sendable {
    guard index < callbacks.count else { return try await terminal() }
    let callback = callbacks[index]
    index += 1
    let called = Box(false)
    let guarded = guarded
    return try await callback(args) { [self] in
      if guarded {
        if called.value { throw CordisError.nextCalledMultipleTimes }
        called.value = true
      }
      return try await run()
    }
  }
}

/// The event bus (port of cordis `events.ts`).
///
/// Bail rule: `onBail` listeners return `K.Result?`; `nil` continues
/// dispatch and any non-nil value bails (`serial`/`bail` return it). cordis
/// also treats `false` as "continue"; Swift results are typed, so there is no
/// such case. `on` listeners return `Void` and never bail; events that never
/// bail declare `Result = Never`.
///
/// Listeners may be sync or async. `emit` is synchronous: sync listeners run
/// in order and the first error propagates; async listeners are started as
/// tasks whose errors are logged (cordis drops the promise of an async
/// listener under `emit`). `serial`, `bail` and `waterfall` await every
/// listener in order; `parallel` runs them concurrently.
@CordisActor
public final class EventsService {
  private unowned let root: Context
  private var counter: UInt64 = 0
  private(set) var hooks: [String: [Hook]] = [:]

  init(root: Context) {
    self.root = root
    // runs the target fiber's own update hooks as an onion (`events.ts:62-67`)
    _ = try? register(
      label: "ctx.on(\"\(UpdateEvent.name)\")",
      name: UpdateEvent.name,
      ctx: root,
      options: EventOptions(prepend: true, global: true),
      callback: .waterfall { args, next in
        let fiber = (args as! UpdateEvent.Args).fiber
        return try await Onion(callbacks: fiber.updateHooks.values, args: args, guarded: false, terminal: next).run()
      }
    )
  }

  /// Number of listeners per event name (leak checks).
  public var snapshot: [String: Int] {
    hooks.mapValues(\.count).filter { $0.value > 0 }
  }

  func register(label: String, name: String, ctx: Context, options: EventOptions, callback: HookCallback) throws -> (EffectHandle, UInt64) {
    counter += 1
    let id = counter
    let handle = try ctx.fiber.effect(label, sync: { [self] in
      let hook = Hook(id: id, ctx: ctx, global: options.global, callback: callback)
      if options.prepend {
        hooks[name, default: []].insert(hook, at: 0)
      } else {
        hooks[name, default: []].append(hook)
      }
      return { [self] in unregister(name, id) }
    })
    return (handle, id)
  }

  func unregister(_ name: String, _ id: UInt64) {
    guard var list = hooks[name], let index = list.firstIndex(where: { $0.id == id }) else { return }
    list.remove(at: index)
    hooks[name] = list.isEmpty ? nil : list
  }

  func resolve(_ name: String, scope: (any EventScope)?) -> [HookCallback] {
    (hooks[name] ?? []).filter { hook in
      hook.global || scope == nil || scope!.filter(hook.ctx)
    }.map(\.callback)
  }

  func on(_ name: String, ctx: Context, options: EventOptions, callback: HookCallback) throws -> (EffectHandle, UInt64) {
    try ctx.fiber.assertActive()
    let label = "ctx.on(\"\(name)\")"
    if name == UpdateEvent.name && !options.global, case .waterfall(let waterfall) = callback {
      let fiber = ctx.fiber
      counter += 1
      let id = counter
      let handle = try fiber.effect(label, sync: {
        let token = fiber.updateHooks.push(waterfall)
        return { fiber.updateHooks.delete(token) }
      })
      return (handle, id)
    }
    return try register(label: label, name: name, ctx: ctx, options: options, callback: callback)
  }

  func emit(_ name: String, _ args: any Sendable, scope: (any EventScope)?) throws {
    for callback in resolve(name, scope: scope) {
      switch callback {
      case .sync(let fn):
        _ = try fn(args)
      case .async(let fn):
        let logger = root.logger
        Task { @CordisActor in
          do { _ = try await fn(args) } catch { logger.error(error) }
        }
      case .waterfall:
        continue
      }
    }
  }

  func serial(_ name: String, _ args: any Sendable, scope: (any EventScope)?) async throws -> (any Sendable)? {
    for callback in resolve(name, scope: scope) {
      let result: (any Sendable)?
      switch callback {
      case .sync(let fn): result = try fn(args)
      case .async(let fn): result = try await fn(args)
      case .waterfall: continue
      }
      if let result { return result }
    }
    return nil
  }

  func parallel(_ name: String, _ args: any Sendable, scope: (any EventScope)?) async throws {
    let callbacks = resolve(name, scope: scope)
    let tasks: [Task<Void, any Error>] = callbacks.compactMap { callback in
      switch callback {
      case .sync(let fn): Task { @CordisActor in _ = try fn(args) }
      case .async(let fn): Task { @CordisActor in _ = try await fn(args) }
      case .waterfall: nil
      }
    }
    var errors: [any Error] = []
    for task in tasks {
      if case .failure(let error) = await task.result { errors.append(error) }
    }
    if !errors.isEmpty { throw AggregateError(errors: errors) }
  }

  func waterfall(
    _ name: String,
    _ args: any Sendable,
    scope: (any EventScope)?,
    terminal: @escaping ErasedNext
  ) async throws -> any Sendable {
    let callbacks: [ErasedWaterfall] = resolve(name, scope: scope).compactMap {
      if case .waterfall(let fn) = $0 { return fn }
      return nil
    }
    return try await Onion(callbacks: callbacks, args: args, guarded: true, terminal: terminal).run()
  }
}

// MARK: - Context API

extension Context {
  /// Listens to `key` until the returned effect is disposed (or this
  /// context's fiber unloads). The listener never bails; use `onBail` for
  /// listeners that may return a result.
  @discardableResult
  public func on<K: EventKey>(
    _ key: K.Type,
    options: EventOptions = EventOptions(),
    _ listener: @escaping @CordisActor (K.Args) throws -> Void
  ) throws -> EffectHandle {
    try events.on(K.name, ctx: self, options: options, callback: .sync { try listener($0 as! K.Args); return nil }).0
  }

  @discardableResult
  public func on<K: EventKey>(
    _ key: K.Type,
    options: EventOptions = EventOptions(),
    _ listener: @escaping @CordisActor (K.Args) async throws -> Void
  ) throws -> EffectHandle {
    try events.on(K.name, ctx: self, options: options, callback: .async { try await listener($0 as! K.Args); return nil }).0
  }

  /// Listens to `key` with a listener that may bail: a non-nil result stops
  /// `serial`/`bail` dispatch and is returned to the dispatcher.
  @discardableResult
  public func onBail<K: EventKey>(
    _ key: K.Type,
    options: EventOptions = EventOptions(),
    _ listener: @escaping @CordisActor (K.Args) throws -> K.Result?
  ) throws -> EffectHandle {
    try events.on(K.name, ctx: self, options: options, callback: .sync { try listener($0 as! K.Args) }).0
  }

  @discardableResult
  public func onBail<K: EventKey>(
    _ key: K.Type,
    options: EventOptions = EventOptions(),
    _ listener: @escaping @CordisActor (K.Args) async throws -> K.Result?
  ) throws -> EffectHandle {
    try events.on(K.name, ctx: self, options: options, callback: .async { try await listener($0 as! K.Args) }).0
  }

  /// Waterfall listener: call `next` to continue to later listeners and the
  /// caller's terminal continuation, at most once.
  @discardableResult
  public func on<K: EventKey>(
    _ key: K.Type,
    options: EventOptions = EventOptions(),
    _ listener: @escaping @CordisActor (K.Args, _ next: @escaping @CordisActor () async throws -> K.Result) async throws -> K.Result
  ) throws -> EffectHandle {
    try events.on(K.name, ctx: self, options: options, callback: .waterfall { args, next in
      try await listener(args as! K.Args) { try await next() as! K.Result }
    }).0
  }

  /// Listens to the first dispatch of `key` only.
  @discardableResult
  public func once<K: EventKey>(
    _ key: K.Type,
    options: EventOptions = EventOptions(),
    _ listener: @escaping @CordisActor (K.Args) throws -> Void
  ) throws -> EffectHandle {
    let events = events
    let id = Box<UInt64>(0)
    let (handle, hookID) = try events.on(K.name, ctx: self, options: options, callback: .sync {
      events.unregister(K.name, id.value)
      try listener($0 as! K.Args)
      return nil
    })
    id.value = hookID
    return handle
  }

  /// Synchronous dispatch; see `EventsService` for async listeners.
  public func emit<K: EventKey>(scope: (any EventScope)? = nil, _ key: K.Type, _ args: K.Args) throws {
    try events.emit(K.name, args, scope: scope)
  }

  public func emit<K: EventKey>(scope: (any EventScope)? = nil, _ key: K.Type) throws where K.Args == Void {
    try events.emit(K.name, (), scope: scope)
  }

  /// Runs listeners concurrently; failures are collected into `AggregateError`.
  public func parallel<K: EventKey>(scope: (any EventScope)? = nil, _ key: K.Type, _ args: K.Args) async throws {
    try await events.parallel(K.name, args, scope: scope)
  }

  public func parallel<K: EventKey>(scope: (any EventScope)? = nil, _ key: K.Type) async throws where K.Args == Void {
    try await events.parallel(K.name, (), scope: scope)
  }

  /// Runs listeners in order; returns the first non-nil result.
  @discardableResult
  public func serial<K: EventKey>(scope: (any EventScope)? = nil, _ key: K.Type, _ args: K.Args) async throws -> K.Result? {
    try await events.serial(K.name, args, scope: scope) as? K.Result
  }

  @discardableResult
  public func serial<K: EventKey>(scope: (any EventScope)? = nil, _ key: K.Type) async throws -> K.Result? where K.Args == Void {
    try await events.serial(K.name, (), scope: scope) as? K.Result
  }

  /// Same as `serial`; kept for API parity with cordis.
  @discardableResult
  public func bail<K: EventKey>(scope: (any EventScope)? = nil, _ key: K.Type, _ args: K.Args) async throws -> K.Result? {
    try await serial(scope: scope, key, args)
  }

  @discardableResult
  public func bail<K: EventKey>(scope: (any EventScope)? = nil, _ key: K.Type) async throws -> K.Result? where K.Args == Void {
    try await serial(scope: scope, key, ())
  }

  /// Onion dispatch: each waterfall listener receives `next`; when all have
  /// called through, `terminal` produces the result.
  @discardableResult
  public func waterfall<K: EventKey>(
    scope: (any EventScope)? = nil,
    _ key: K.Type,
    _ args: K.Args,
    _ terminal: @escaping @CordisActor () async throws -> K.Result
  ) async throws -> K.Result {
    try await events.waterfall(K.name, args, scope: scope, terminal: { try await terminal() }) as! K.Result
  }

  /// Dispatches a core event; listener errors are logged, not thrown.
  func emitInternal<K: EventKey>(_ key: K.Type, _ args: K.Args, scope: (any EventScope)? = nil) {
    do {
      try events.emit(K.name, args, scope: scope)
    } catch {
      logger.error(error)
    }
  }
}

/// Mutable reference cell isolated to `CordisActor`.
@CordisActor
public final class Box<Value> {
  public var value: Value

  public init(_ value: Value) {
    self.value = value
  }
}
