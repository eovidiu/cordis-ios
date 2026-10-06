import Foundation

/// A JSON document. Used for persisted plugin configs (loader entries) and as
/// one of the accepted raw config forms in `Fiber.update`.
public enum JSONValue: Codable, Sendable, Equatable {
  case null
  case bool(Bool)
  case number(Double)
  case string(String)
  case array([JSONValue])
  case object([String: JSONValue])

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([JSONValue].self) {
      self = .array(value)
    } else {
      self = .object(try container.decode([String: JSONValue].self))
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .null: try container.encodeNil()
    case .bool(let value): try container.encode(value)
    case .number(let value): try container.encode(value)
    case .string(let value): try container.encode(value)
    case .array(let value): try container.encode(value)
    case .object(let value): try container.encode(value)
    }
  }

  /// Encodes any `Encodable` value as a `JSONValue`.
  public init<T: Encodable>(encoding value: T) throws {
    let data = try JSONEncoder().encode(value)
    self = try JSONDecoder().decode(JSONValue.self, from: data)
  }

  /// Decodes this document into `T`.
  public func decode<T: Decodable>(as type: T.Type = T.self) throws -> T {
    try JSONDecoder().decode(T.self, from: JSONEncoder().encode(self))
  }
}
