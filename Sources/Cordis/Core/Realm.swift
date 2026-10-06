/// An isolation realm: the Swift replacement for the `Symbol` labels cordis
/// stores in `ctx[Context.isolate]`. Two contexts see the same service
/// instance for a name only when their isolate tables map that name to the
/// same realm. Realms are minted per root by `Context.makeRealm(name:)`.
public struct Realm: Hashable, Sendable, CustomStringConvertible {
  public let id: UInt64
  public let name: String

  public var description: String { "Realm(\(name)#\(id))" }
}
