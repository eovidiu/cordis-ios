/// Maps the plugin names used in entries to plugins.
public struct PluginCatalog: Sendable {
  private var plugins: [String: any AnyPlugin] = [:]

  public init() {}

  public mutating func register<P: Plugin>(_ type: P.Type, as name: String = P.name) {
    plugins[name] = PluginType<P>()
  }

  public mutating func register(_ plugin: some AnyPlugin, as name: String) {
    plugins[name] = plugin
  }

  public func resolve(_ name: String) -> (any AnyPlugin)? {
    plugins[name]
  }

  public var names: [String] { plugins.keys.sorted() }
}
