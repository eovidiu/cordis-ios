/// One persisted plugin entry (paper §5.2.1). `plugin` is a catalog name
/// (cordis `url`); an entry with `children` is a group.
public struct Entry: Codable, Sendable, Equatable, Identifiable {
  public var id: String
  public var plugin: String
  public var config: JSONValue?
  public var disabled: Bool
  /// Service name → realm the entry's context resolves it in.
  public var isolate: [String: IsolateSpec]?
  public var children: [Entry]?

  public init(
    id: String,
    plugin: String,
    config: JSONValue? = nil,
    disabled: Bool = false,
    isolate: [String: IsolateSpec]? = nil,
    children: [Entry]? = nil
  ) {
    self.id = id
    self.plugin = plugin
    self.config = config
    self.disabled = disabled
    self.isolate = isolate
    self.children = children
  }

  private enum CodingKeys: String, CodingKey {
    case id, plugin, config, disabled, isolate, children
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    plugin = try container.decode(String.self, forKey: .plugin)
    config = try container.decodeIfPresent(JSONValue.self, forKey: .config)
    disabled = try container.decodeIfPresent(Bool.self, forKey: .disabled) ?? false
    isolate = try container.decodeIfPresent([String: IsolateSpec].self, forKey: .isolate)
    children = try container.decodeIfPresent([Entry].self, forKey: .children)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(plugin, forKey: .plugin)
    try container.encodeIfPresent(config, forKey: .config)
    if disabled { try container.encode(true, forKey: .disabled) }
    try container.encodeIfPresent(isolate, forKey: .isolate)
    try container.encodeIfPresent(children, forKey: .children)
  }
}

/// How an entry isolates a service name: `true` in JSON is a realm private
/// to the entry, a string is a realm shared by every entry naming it.
public enum IsolateSpec: Codable, Sendable, Equatable {
  case local
  case shared(String)

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let flag = try? container.decode(Bool.self), flag {
      self = .local
    } else {
      self = .shared(try container.decode(String.self))
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .local: try container.encode(true)
    case .shared(let name): try container.encode(name)
    }
  }
}
