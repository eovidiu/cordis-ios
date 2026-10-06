/// Per-plugin bookkeeping shared by all fibers of one plugin (cordis
/// `Plugin.Runtime`).
@CordisActor
public final class Runtime {
  public let name: String?
  public let identity: PluginIdentity
  let injections: [Injection]
  let run: @CordisActor (Context, (any Sendable)?, EffectScope) async throws -> Void
  let resolveConfig: @CordisActor ((any Sendable)?) throws -> (any Sendable)?
  var fibers = DisposableList<Fiber>()
  private let anchor: AnyObject?

  init(
    name: String?,
    identity: PluginIdentity,
    injections: [Injection],
    run: @escaping @CordisActor (Context, (any Sendable)?, EffectScope) async throws -> Void,
    resolveConfig: @escaping @CordisActor ((any Sendable)?) throws -> (any Sendable)?,
    anchor: AnyObject? = nil
  ) {
    self.name = name
    self.identity = identity
    self.injections = injections
    self.run = run
    self.resolveConfig = resolveConfig
    self.anchor = anchor
  }

  /// Live fibers of this plugin, oldest first.
  public var fiberList: [Fiber] { fibers.values }
}

/// The plugin registry (port of cordis `registry.ts`).
@CordisActor
public final class RegistryService {
  private var _counter = 0
  private var internalMap: [PluginIdentity: Runtime] = [:]
  private var order: [PluginIdentity] = []

  init() {}

  /// Last fiber uid handed out.
  public var counter: Int { _counter }

  func nextUID() -> Int {
    _counter += 1
    return _counter
  }

  public var size: Int { internalMap.count }

  /// Runtimes in registration order.
  public var runtimes: [Runtime] { order.compactMap { internalMap[$0] } }

  public func get(_ identity: PluginIdentity) -> Runtime? { internalMap[identity] }
  public func get<P: Plugin>(_ type: P.Type) -> Runtime? { get(PluginType<P>().identity) }
  public func get(_ plugin: some AnyPlugin) -> Runtime? { get(plugin.identity) }

  public func has(_ identity: PluginIdentity) -> Bool { internalMap[identity] != nil }
  public func has<P: Plugin>(_ type: P.Type) -> Bool { has(PluginType<P>().identity) }
  public func has(_ plugin: some AnyPlugin) -> Bool { has(plugin.identity) }

  /// Removes the plugin and disposes all of its fibers.
  @discardableResult
  public func delete(_ identity: PluginIdentity) async -> Runtime? {
    guard let runtime = remove(identity) else { return nil }
    for fiber in runtime.fibers.values {
      try? await fiber.dispose()
    }
    return runtime
  }

  @discardableResult
  public func delete<P: Plugin>(_ type: P.Type) async -> Runtime? { await delete(PluginType<P>().identity) }
  @discardableResult
  public func delete(_ plugin: some AnyPlugin) async -> Runtime? { await delete(plugin.identity) }

  @discardableResult
  func remove(_ identity: PluginIdentity) -> Runtime? {
    guard let runtime = internalMap.removeValue(forKey: identity) else { return nil }
    order.removeAll { $0 == identity }
    return runtime
  }

  func plugin<P: Plugin>(_ type: P.Type, config: P.Config?, in ctx: Context) throws -> Fiber {
    try plugin(PluginType<P>(), rawConfig: config, in: ctx)
  }

  func plugin<C>(_ plugin: FunctionPlugin<C>, config: C?, in ctx: Context) throws -> Fiber {
    try self.plugin(plugin, rawConfig: config, in: ctx)
  }

  /// `registry.ts:193-214`: find or create the runtime, then a fiber under `ctx`.
  func plugin(_ plugin: any AnyPlugin, rawConfig: (any Sendable)?, in ctx: Context) throws -> Fiber {
    try ctx.fiber.assertActive()
    let identity = plugin.identity
    let runtime: Runtime
    if let existing = internalMap[identity] {
      runtime = existing
    } else {
      runtime = plugin.makeRuntime()
      internalMap[identity] = runtime
      order.append(identity)
    }
    let fiber = Fiber(parent: ctx, uid: nextUID(), injections: runtime.injections, runtime: runtime)
    try fiber.start(rawConfig: rawConfig)
    return fiber
  }
}
