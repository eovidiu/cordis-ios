import Foundation

/// Config of a plugin that takes none. Decodes from `{}` or `null`.
public struct NoConfig: Codable, Sendable, Equatable {
  public init() {}
}

/// A dependency declaration: service `name`, plus an optional interception
/// config the plugin's context receives for it (cordis `inject: { name: config }`).
public struct Injection: Sendable {
  public let name: String
  public let config: (any Sendable)?

  public init<K: ServiceKey>(_ key: K.Type, config: (any Sendable)? = nil) {
    self.name = K.name
    self.config = config
  }

  public init(name: String, config: (any Sendable)? = nil) {
    self.name = name
    self.config = config
  }

  public static func inject(_ keys: [any ServiceKey.Type]) -> [Injection] {
    keys.map { Injection(name: $0.name, config: nil) }
  }
}

/// A plugin type (cordis class plugin). An instance is created for every
/// (re)load with the fiber's context and validated config; `apply` installs
/// its effects. Plugins are isolated to `CordisActor`, so they may keep
/// mutable state.
@CordisActor
public protocol Plugin: AnyObject, Sendable {
  associatedtype Config: Decodable & Sendable = NoConfig
  /// Runtime name (`fiber.name`, logger name). Default: the type name.
  nonisolated static var name: String { get }
  /// Services that must be provided for the plugin to run.
  nonisolated static var inject: [any ServiceKey.Type] { get }
  /// `inject` with per-service interception configs.
  nonisolated static var injections: [Injection] { get }
  nonisolated static func validate(_ config: Config) throws
  init(ctx: Context, config: Config)
  func apply(_ scope: EffectScope) async throws
}

extension Plugin {
  public nonisolated static var name: String { String(describing: Self.self) }
  public nonisolated static var inject: [any ServiceKey.Type] { [] }
  public nonisolated static var injections: [Injection] { Injection.inject(inject) }
  public nonisolated static func validate(_ config: Config) throws {}
}

/// Identity of a plugin in the registry: plugging the same identity twice
/// shares one `Runtime`, as a JS function reference does.
public enum PluginIdentity: Hashable, Sendable {
  case type(ObjectIdentifier)
  case function(ObjectIdentifier)
}

/// Anything the registry can plug.
public protocol AnyPlugin: Sendable {
  var identity: PluginIdentity { get }
  @CordisActor func makeRuntime() -> Runtime
}

/// Type-erased wrapper around a `Plugin` type.
public struct PluginType<P: Plugin>: AnyPlugin {
  public init(_ type: P.Type = P.self) {}

  public var identity: PluginIdentity { .type(ObjectIdentifier(P.self)) }

  @CordisActor
  public func makeRuntime() -> Runtime {
    Runtime(
      name: P.name,
      identity: identity,
      injections: P.injections,
      run: { ctx, config, scope in
        guard let config = config as? P.Config else {
          throw ValidationError(issues: [ValidationIssue(message: "expected \(P.Config.self)")])
        }
        let plugin = P(ctx: ctx, config: config)
        try await plugin.apply(scope)
      },
      resolveConfig: { raw in try resolveConfig(raw, as: P.Config.self, validate: { try P.validate($0) }) }
    )
  }
}

final class PluginAnchor: Sendable {}

/// A closure plugin (cordis function plugin). Each value has its own
/// identity; re-plugging the same value shares one runtime.
public struct FunctionPlugin<Config: Decodable & Sendable>: AnyPlugin {
  public typealias Apply = @CordisActor @Sendable (Context, Config, EffectScope) async throws -> Void

  public let name: String?
  public let injections: [Injection]
  let body: Apply
  let validator: (@Sendable (Config) throws -> Void)?
  let anchor = PluginAnchor()

  public init(
    name: String? = nil,
    inject: [any ServiceKey.Type] = [],
    injections: [Injection] = [],
    validate: (@Sendable (Config) throws -> Void)? = nil,
    apply: @escaping Apply
  ) {
    self.name = name
    self.injections = Injection.inject(inject) + injections
    self.body = apply
    self.validator = validate
  }

  public var identity: PluginIdentity { .function(ObjectIdentifier(anchor)) }

  @CordisActor
  public func makeRuntime() -> Runtime {
    let body = body
    let validator = validator
    return Runtime(
      name: name,
      identity: identity,
      injections: injections,
      run: { ctx, config, scope in
        guard let config = config as? Config else {
          throw ValidationError(issues: [ValidationIssue(message: "expected \(Config.self)")])
        }
        try await body(ctx, config, scope)
      },
      resolveConfig: { raw in try resolveConfig(raw, as: Config.self, validate: validator ?? { _ in }) },
      anchor: anchor
    )
  }
}

/// Turns a raw config into `C`: a `C` value is used as is, `nil`/`JSONValue`
/// are decoded (nil as `{}`), then `validate` runs. Failures become
/// `ValidationError`.
func resolveConfig<C: Decodable & Sendable>(
  _ raw: (any Sendable)?,
  as type: C.Type,
  validate: (C) throws -> Void
) throws -> C {
  let value: C
  if let typed = raw as? C {
    value = typed
  } else {
    let json: JSONValue
    switch raw {
    case nil: json = .object([:])
    case let document as JSONValue: json = document == .null ? .object([:]) : document
    case let some?:
      throw ValidationError(issues: [ValidationIssue(message: "expected \(C.self), received \(Swift.type(of: some))")])
    }
    do {
      value = try json.decode(as: C.self)
    } catch let error as DecodingError {
      throw ValidationError(issues: [ValidationIssue(decoding: error)])
    }
  }
  do {
    try validate(value)
  } catch let error as ValidationError {
    throw error
  } catch {
    throw ValidationError(issues: [ValidationIssue(message: String(describing: error))])
  }
  return value
}

extension ValidationIssue {
  init(decoding error: DecodingError) {
    let context: DecodingError.Context
    let message: String
    switch error {
    case .typeMismatch(let type, let ctx):
      context = ctx
      message = "expected \(type)"
    case .valueNotFound(let type, let ctx):
      context = ctx
      message = "missing value of type \(type)"
    case .keyNotFound(let key, let ctx):
      context = ctx
      message = "missing key \"\(key.stringValue)\""
    case .dataCorrupted(let ctx):
      context = ctx
      message = ctx.debugDescription
    @unknown default:
      self.init(message: String(describing: error))
      return
    }
    var path = context.codingPath.map(\.stringValue)
    if case .keyNotFound(let key, _) = error { path.append(key.stringValue) }
    self.init(message: message, path: path)
  }
}
