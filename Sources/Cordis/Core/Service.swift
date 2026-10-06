/// A plugin that provides itself as service `Key` (cordis `Service`). The
/// service is provided when the plugin applies, before `setup` runs, and
/// consumers start once the providing fiber becomes active, i.e. after
/// `setup` returns.
public protocol ServicePlugin: Plugin {
  associatedtype Key: ServiceKey where Key.Value == Self
  var ctx: Context { get }
  /// Runs after the service is provided (cordis `[Service.init]`).
  func setup(_ scope: EffectScope) async throws
  /// Whether consumers may use the service right now (cordis `[Service.check]`).
  func check() -> Bool
}

extension ServicePlugin {
  public nonisolated static var name: String { Key.name }

  public func setup(_ scope: EffectScope) async throws {}

  public func check() -> Bool { true }

  public func apply(_ scope: EffectScope) async throws {
    try ctx.provide(Key.self, self, check: { [unowned self] in self.check() })
    try await setup(scope)
  }

  /// Scope for events this service emits: only listeners in the service's
  /// realm receive them.
  public var eventScope: IsolationScope { IsolationScope(ctx: ctx, name: Key.name) }
}
