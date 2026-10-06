/// Lifecycle state of a fiber (cordis `FiberState`).
public enum FiberState: Int, Sendable, CustomStringConvertible {
  case pending = 0
  case loading = 1
  case active = 2
  case failed = 3
  case disposed = 4
  case unloading = 5

  public var description: String {
    switch self {
    case .pending: "pending"
    case .loading: "loading"
    case .active: "active"
    case .failed: "failed"
    case .disposed: "disposed"
    case .unloading: "unloading"
    }
  }
}

/// A running instance of a plugin (port of cordis `fiber.ts`). The fiber
/// owns the effects its plugin installed and reloads or unloads the plugin
/// as the services it injects come and go. Transitions run as tasks stored
/// in `inertia`; a transition in flight always runs to completion, and a
/// change that arrives meanwhile is applied when it finishes.
@CordisActor
public final class Fiber {
  static let inactive = "__INACTIVE__"

  public internal(set) var uid: Int?
  public let parent: Context
  public internal(set) var config: (any Sendable)?
  public private(set) var state: FiberState = .pending
  /// Services visible to this fiber's plugin while it is loaded.
  public internal(set) var store: [String: Impl]?
  /// The lifecycle transition in flight, if any.
  public internal(set) var inertia: Task<Void, Never>?
  /// Injected service names → interception config (nil when none).
  public let inject: [String: (any Sendable)?]
  public let runtime: Runtime?
  public internal(set) var error: (any Error)?

  var disposables = DisposableList<FiberDisposable>()
  var updateHooks = DisposableList<ErasedWaterfall>()

  private var _ctx: Context?
  private let injectNames: [String]
  private var epoch: String
  private var staged: [String: Impl] = [:]
  private var disposeHandle: EffectHandle?

  /// The fiber's own context (`ctx.fiber === self`).
  public var ctx: Context { _ctx! }

  /// Root fiber (`runtime == nil`), always active.
  init(root: Context) {
    uid = 0
    parent = root
    inject = [:]
    injectNames = []
    runtime = nil
    state = .active
    store = [:]
    epoch = ""
    _ctx = root
  }

  init(parent: Context, uid: Int, injections: [Injection], runtime: Runtime) {
    self.uid = uid
    self.parent = parent
    var inject: [String: (any Sendable)?] = [:]
    var names: [String] = []
    for injection in injections where inject[injection.name] == nil {
      names.append(injection.name)
      inject[injection.name] = .some(injection.config)
    }
    self.inject = inject
    self.injectNames = names
    self.runtime = runtime
    self.epoch = Self.inactive
  }

  /// Second half of the cordis `Fiber` constructor (`fiber.ts:122-213`).
  func start(rawConfig: (any Sendable)?) throws {
    guard let runtime else { return }
    var intercepts: [String: any Sendable] = [:]
    for name in injectNames {
      if let config = inject[name], let config { intercepts[name] = config }
    }
    _ctx = parent.extend(fiber: self, intercepts: intercepts)

    ctx.emitInternal(PluginEvent.self, self)

    for name in injectNames {
      checkImpl(name)
    }

    disposeHandle = try parent.fiber.effect("ctx.plugin()", sync: { [self] in
      let token = runtime.fibers.push(self)
      do {
        config = try runtime.resolveConfig(rawConfig)
        refresh()
      } catch {
        ctx.logger.error(error)
        self.error = error
        updateState { nil }
      }
      return { [self] in
        uid = nil
        ctx.emitInternal(PluginEvent.self, self)
        let registry = ctx.registry
        if registry.get(runtime.identity) === runtime {
          runtime.fibers.delete(token)
          if runtime.fibers.isEmpty {
            registry.remove(runtime.identity)
          }
        }
        setEpoch(Self.inactive)
        while let inertia {
          await inertia.value
        }
        // cordis leaves a fiber that was pending or failed in that state;
        // settle every disposed fiber on `.disposed`.
        updateState { nil }
      }
    })
  }

  /// Name of the nearest named plugin up the tree, else `"root"`.
  public var name: String {
    var fiber = self
    repeat {
      if let name = fiber.runtime?.name { return name }
      fiber = fiber.parent.fiber
    } while fiber !== fiber.parent.fiber
    return "root"
  }

  public var isRoot: Bool { runtime == nil }

  public func assertActive() throws {
    if uid == nil { throw CordisError.inactiveEffect }
  }

  /// Disposes this fiber (its plugin is unloaded and removed). On the root
  /// fiber this restarts it instead, as in cordis.
  public func dispose() async throws {
    if runtime == nil {
      try await restart()
    } else {
      try await disposeHandle?.dispose()
    }
  }

  // MARK: - state machine (`fiber.ts:342-460`)

  private func computeState() -> FiberState {
    if uid == nil { return .disposed }
    if error != nil { return .failed }
    if epoch != Self.inactive { return .active }
    return .pending
  }

  func updateState(_ body: () -> FiberState?) {
    let oldState = state
    state = body() ?? computeState()
    if oldState == state { return }
    ctx.emitInternal(StatusEvent.self, (fiber: self, oldState: oldState))

    // only notify changes between ACTIVE and NON-ACTIVE states
    if oldState != .active && state != .active { return }
    let reflect = ctx.reflect
    for impl in reflect.store.values where impl.fiber === self {
      reflect.notify([impl.name], from: impl.ctx)
    }
  }

  func checkImpl(_ name: String) {
    guard let impl = ctx.reflect.getImpl(name, in: ctx, strict: true) else {
      staged[name] = nil
      return
    }
    if let check = impl.check, !check() {
      staged[name] = nil
      return
    }
    staged[name] = impl
  }

  func refresh() {
    var epoch = ""
    for name in injectNames {
      guard let impl = staged[name] else {
        epoch = Self.inactive
        break
      }
      epoch += ":" + (impl.fiber.uid.map(String.init) ?? "null")
    }
    setEpoch(epoch)
  }

  private func setEpoch(_ newEpoch: String) {
    let oldEpoch = epoch
    if newEpoch == oldEpoch { return }
    // a failed fiber only recovers through update(), which clears the error
    if error != nil { return }
    epoch = newEpoch
    if inertia != nil { return }
    updateState {
      if newEpoch != Self.inactive && oldEpoch == Self.inactive {
        startReload()
        return .loading
      } else {
        startUnload()
        return .unloading
      }
    }
  }

  private func startReload() {
    store = staged
    let oldEpoch = epoch
    inertia = Task { @CordisActor [self] in
      await reload(oldEpoch: oldEpoch)
    }
  }

  private func startUnload() {
    inertia = Task { @CordisActor [self] in
      await unload()
    }
  }

  private func reload(oldEpoch: String) async {
    do {
      try await execute(oldEpoch: oldEpoch)
    } catch is EffectAbortedError {
      // the plugin stopped at a `collect` after its epoch changed
    } catch {
      ctx.logger.error(error)
      self.error = error
      epoch = Self.inactive
    }
    updateState {
      if epoch == oldEpoch {
        inertia = nil
        return nil
      } else {
        startUnload()
        return .unloading
      }
    }
  }

  private func execute(oldEpoch: String) async throws {
    guard let runtime else { return }
    let scope = EffectScope(
      collect: { [self] dispose in disposables.push(.disposer(dispose)) },
      collectHandle: { _ in },
      isAborted: { [self] in epoch != oldEpoch }
    )
    try await runtime.run(ctx, config, scope)
  }

  private func unload() async {
    let items = disposables.clear()
    // cordis starts every disposer at once (`Promise.all`), each running its
    // synchronous part before other queued work. Swift cannot start a task
    // synchronously on iOS 17, so the disposers run one after another, newest
    // first, inside this task: the synchronous part of the first one still
    // runs before any other queued transition, which keeps cross-fiber
    // ordering the same as cordis.
    for item in items {
      do { try await item.run() } catch { ctx.logger.error(error) }
    }
    store = nil
    updateState {
      if epoch == Self.inactive {
        inertia = nil
        return nil
      } else {
        startReload()
        return .loading
      }
    }
  }

  // MARK: - public lifecycle API

  /// Waits until no transition is in flight, then rethrows the plugin's
  /// error if the fiber failed.
  @discardableResult
  public func `await`() async throws -> Fiber {
    while let inertia {
      await inertia.value
    }
    if let error { throw error }
    return self
  }

  /// Unloads and reloads the plugin with its current config.
  public func restart() async throws {
    let fiber = ctx.fiber
    try fiber.assertActive()
    fiber.setEpoch(Self.inactive)
    fiber.refresh()
    try await fiber.await()
  }

  /// Validates `config`, runs the `internal/update` waterfall (a listener
  /// may veto by not calling `next`), then stores the config, clears a
  /// previous failure and restarts. Rethrows the reload error.
  public func update(_ config: (any Sendable)?, noSave: Bool = false) async throws {
    let fiber = ctx.fiber
    try fiber.assertActive()
    guard let runtime = fiber.runtime else { return }
    let resolved = try runtime.resolveConfig(config)
    try await fiber.ctx.waterfall(UpdateEvent.self, (fiber: fiber, config: resolved, noSave: noSave)) {
      fiber.config = resolved
      fiber.error = nil
      try await fiber.restart()
    }
  }
}
