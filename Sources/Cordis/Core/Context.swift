/// A string-keyed table with parent fallback: the JS prototype chain behind
/// `ctx[Context.isolate]` and `ctx[Context.intercept]`.
@CordisActor
final class ScopedTable<Value> {
  let parent: ScopedTable<Value>?
  var own: [String: Value]

  init(parent: ScopedTable<Value>?, own: [String: Value] = [:]) {
    self.parent = parent
    self.own = own
  }

  func lookup(_ name: String) -> Value? {
    var table: ScopedTable<Value>? = self
    while let current = table {
      if let value = current.own[name] { return value }
      table = current.parent
    }
    return nil
  }
}

/// The root services shared by every context of one tree.
@CordisActor
final class RootServices {
  var reflect: ReflectService!
  var registry: RegistryService!
  var events: EventsService!
  var logger: LoggerService!
  var realmCounter: UInt64 = 0
}

/// A cordis context: the handle through which plugins install effects, read
/// and provide services and listen to events. `Context()` creates a root;
/// every other context derives from one (`extend`, `isolate`, `intercept`,
/// or a plugin's fiber).
@CordisActor
public final class Context {
  private let rootRef: Context?
  public let parent: Context?
  private var _fiber: Fiber?
  private let services: RootServices
  let isolateTable: ScopedTable<Realm>
  let interceptTable: ScopedTable<any Sendable>

  /// Creates a root context with its root fiber and core services.
  public init() {
    rootRef = nil
    parent = nil
    services = RootServices()
    isolateTable = ScopedTable(parent: nil)
    interceptTable = ScopedTable(parent: nil)
    let fiber = Fiber(root: self)
    _fiber = fiber
    services.reflect = ReflectService(root: self)
    services.registry = RegistryService()
    services.logger = LoggerService()
    services.events = EventsService(root: self)
    services.logger.installDefaultExporter(on: self)
    // the core's own effects are not undone by restarting the root fiber
    _ = fiber.disposables.clear()
  }

  private init(
    parent: Context,
    fiber: Fiber,
    isolate: ScopedTable<Realm>,
    intercept: ScopedTable<any Sendable>
  ) {
    rootRef = parent.root
    self.parent = parent
    services = parent.services
    _fiber = fiber
    isolateTable = isolate
    interceptTable = intercept
  }

  public var root: Context { rootRef ?? self }
  public var isRoot: Bool { rootRef == nil }
  public var fiber: Fiber { _fiber! }

  public var reflect: ReflectService { services.reflect }
  public var registry: RegistryService { services.registry }
  public var events: EventsService { services.events }
  /// A logger bound to this context (its name follows this context).
  public var logger: Logger { Logger(ctx: self, explicitName: nil) }
  var loggerService: LoggerService { services.logger }

  // MARK: - derivation

  /// A child context with the same fiber and tables.
  public func extend() -> Context {
    Context(parent: self, fiber: fiber, isolate: isolateTable, intercept: interceptTable)
  }

  /// A child context bound to `fiber`, with an intercept layer holding the
  /// fiber's inject configs (`fiber.ts:137-144`).
  func extend(fiber: Fiber, intercepts: [String: any Sendable] = [:]) -> Context {
    let intercept = intercepts.isEmpty ? interceptTable : ScopedTable(parent: interceptTable, own: intercepts)
    return Context(parent: self, fiber: fiber, isolate: isolateTable, intercept: intercept)
  }

  /// A child context that resolves service `name` in its own realm: a fresh
  /// one, or `realm` to share it with other contexts.
  public func isolate(_ name: String, realm: Realm? = nil) -> Context {
    let table = ScopedTable(parent: isolateTable, own: [name: realm ?? makeRealm(name: name)])
    return Context(parent: self, fiber: fiber, isolate: table, intercept: interceptTable)
  }

  public func isolate<K: ServiceKey>(_ key: K.Type, realm: Realm? = nil) -> Context {
    isolate(K.name, realm: realm)
  }

  /// A child context carrying interception config for `key`.
  public func intercept<K: InterceptKey>(_ key: K.Type, _ config: K.Config) -> Context {
    let table = ScopedTable<any Sendable>(parent: interceptTable, own: [K.name: config])
    return Context(parent: self, fiber: fiber, isolate: isolateTable, intercept: table)
  }

  /// The nearest interception config for `key`.
  public func interceptConfig<K: InterceptKey>(_ key: K.Type) -> K.Config? {
    interceptTable.lookup(K.name) as? K.Config
  }

  /// The realm this context resolves `name` in (nil before anything was
  /// provided under that name in the root realm and no isolation applies).
  public func realm(of name: String) -> Realm? {
    isolateTable.lookup(name)
  }

  /// Mints a realm unique within this root.
  public func makeRealm(name: String) -> Realm {
    let services = root.services
    services.realmCounter += 1
    return Realm(id: services.realmCounter, name: name)
  }

  // MARK: - services (paper Algorithm 6)

  /// Reads an injected service. Inside a plugin the service must be declared
  /// in the plugin's inject list (or one of its ancestors' in the same
  /// realm); on the root context any provided service is returned.
  public subscript<K: ServiceKey>(_ key: K.Type) -> K.Value {
    get throws {
      let name = K.name
      if fiber.runtime == nil {
        guard let impl = reflect.getImpl(name, in: self, strict: false) else {
          throw CordisError.missingInject(name)
        }
        return try Self.cast(impl, as: K.self)
      }
      let realm = isolateTable.lookup(name)
      var current = fiber
      while true {
        if let impl = current.store?[name] {
          return try Self.cast(impl, as: K.self)
        }
        if current.inject.keys.contains(name) {
          throw CordisError.inactiveService(name)
        }
        if current.runtime == nil {
          throw CordisError.missingInject(name)
        }
        if current.parent.isolateTable.lookup(name) != realm {
          throw CordisError.missingInject(name)
        }
        current = current.parent.fiber
      }
    }
  }

  private static func cast<K: ServiceKey>(_ impl: Impl, as key: K.Type) throws -> K.Value {
    guard let value = impl.value else { throw CordisError.missingInject(K.name) }
    guard let typed = value as? K.Value else {
      throw CordisError.propertyType(K.name, String(describing: type(of: value)))
    }
    return typed
  }

  /// The provided value for `key` in this context's realm, without inject
  /// checks. `strict` hides services whose provider is not active.
  public func get<K: ServiceKey>(_ key: K.Type, strict: Bool = true) -> K.Value? {
    reflect.getImpl(K.name, in: self, strict: strict)?.value as? K.Value
  }

  /// Replaces the value of a service this context's fiber provides.
  public func set<K: ServiceKey>(_ key: K.Type, _ value: K.Value) throws {
    try reflect.set(K.name, value, in: self)
  }

  /// Provides `key` from this context's fiber until the returned effect is
  /// disposed. `check` gates whether consumers may use the value.
  @discardableResult
  public func provide<K: ServiceKey>(
    _ key: K.Type,
    _ value: K.Value? = nil,
    check: (@CordisActor () -> Bool)? = nil
  ) throws -> EffectHandle {
    try reflect.provide(K.name, value, check: check, in: self)
  }

  // MARK: - plugins and effects

  @discardableResult
  public func plugin<P: Plugin>(_ type: P.Type, config: P.Config? = nil) throws -> Fiber {
    try registry.plugin(type, config: config, in: self)
  }

  @discardableResult
  public func plugin<C>(_ plugin: FunctionPlugin<C>, config: C? = nil) throws -> Fiber {
    try registry.plugin(plugin, config: config, in: self)
  }

  /// Plugs a type-erased plugin with a raw config (`JSONValue`, a typed
  /// config, or nil).
  @discardableResult
  public func plugin(_ plugin: any AnyPlugin, rawConfig: (any Sendable)?) throws -> Fiber {
    try registry.plugin(plugin, rawConfig: rawConfig, in: self)
  }

  /// Runs `body` as an anonymous plugin while every key in `keys` is provided.
  @discardableResult
  public func inject(
    _ keys: [any ServiceKey.Type],
    _ body: @escaping @CordisActor @Sendable (Context, EffectScope) async throws -> Void
  ) throws -> Fiber {
    try plugin(FunctionPlugin<NoConfig>(inject: keys) { ctx, _, scope in try await body(ctx, scope) })
  }

  @discardableResult
  public func effect(_ label: String = "anonymous", sync execute: () throws -> Disposer?) throws -> EffectHandle {
    try fiber.effect(label, sync: execute)
  }

  @discardableResult
  public func effect(_ label: String = "anonymous", scoped execute: (EffectScope) throws -> Void) throws -> EffectHandle {
    try fiber.effect(label, scoped: execute)
  }

  @discardableResult
  public func effect(
    _ label: String = "anonymous",
    _ execute: @escaping @CordisActor @Sendable (EffectScope) async throws -> Void
  ) throws -> EffectHandle {
    try fiber.effect(label, execute)
  }
}

extension Context: @CordisActor CustomStringConvertible {
  public var description: String { "Context <\(fiber.name)>" }
}
