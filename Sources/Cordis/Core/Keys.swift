/// A typed service slot. `name` is the runtime key (cordis's property name);
/// it is used for isolation tables, error messages and `internal/service`.
public protocol ServiceKey: SendableMetatype {
  associatedtype Value: Sendable
  static var name: String { get }
}

/// A typed interception slot (`ctx.intercept(name, config)` in cordis).
public protocol InterceptKey: SendableMetatype {
  associatedtype Config: Sendable
  static var name: String { get }
}

/// A typed event. `Result` is the bail value for `serial`/`bail` and the
/// return value for `waterfall`. Events that never bail use `Result = Never`.
public protocol EventKey: SendableMetatype {
  associatedtype Args: Sendable
  associatedtype Result: Sendable
  static var name: String { get }
}
