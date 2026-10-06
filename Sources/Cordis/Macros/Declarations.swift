/// Makes a `final class` a plugin: generates `ctx`, `config`,
/// `init(ctx:config:)` and `inject` (one entry per `@Inject` property, in
/// source order), and adds the `Plugin` conformance. `config` has the class's
/// `typealias Config`, or `NoConfig` when there is none. Mark the class
/// `@CordisActor`.
///
/// ```swift
/// @CordisActor @Plugin
/// final class Greeter {
///   @Inject(ClockKey.self) var clock: ClockService
///   func apply(_ scope: EffectScope) async throws { … }
/// }
/// ```
@attached(member, names: named(ctx), named(config), named(init(ctx:config:)), named(inject))
@attached(extension, conformances: Plugin)
public macro Plugin() = #externalMacro(module: "CordisMacros", type: "PluginMacro")

/// Declares a dependency and reads it: `@Inject(Key.self) var name: Value`
/// becomes `get throws { try ctx[Key.self] }`, and the enclosing `@Plugin`
/// or `@Service` class lists `Key` in its `inject`.
@attached(accessor)
public macro Inject<K: ServiceKey>(_ key: K.Type) = #externalMacro(module: "CordisMacros", type: "InjectMacro")

/// Like `@Plugin`, for a class that provides itself as service `key`: adds
/// `typealias Key` and the `ServicePlugin` conformance.
@attached(member, names: named(Key), named(ctx), named(config), named(init(ctx:config:)), named(inject))
@attached(extension, conformances: ServicePlugin)
public macro Service<K: ServiceKey>(_ key: K.Type) = #externalMacro(module: "CordisMacros", type: "ServiceMacro")
