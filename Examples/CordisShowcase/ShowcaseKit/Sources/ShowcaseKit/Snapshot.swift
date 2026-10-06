import Cordis
import Foundation

/// Display state of a loader entry.
public enum EntryState: String, Sendable, CaseIterable {
  case pending, loading, active, failed, unloading, disposed
  /// The entry itself is disabled.
  case disabled
  /// An enclosing group is disabled, so the entry has no fiber.
  case inactive
  /// The entry names a plugin missing from the catalog.
  case unknown

  init(_ state: FiberState) {
    switch state {
    case .pending: self = .pending
    case .loading: self = .loading
    case .active: self = .active
    case .failed: self = .failed
    case .disposed: self = .disposed
    case .unloading: self = .unloading
    }
  }
}

/// One injected service of an entry and whether it is usable right now
/// (nil when the entry has no fiber to resolve it from).
public struct Dependency: Sendable, Hashable {
  public let name: String
  public let available: Bool?
}

/// One live effect of a fiber, flattened with its nesting depth.
public struct EffectLine: Sendable, Hashable {
  public let label: String
  public let depth: Int
}

/// A loader entry with its fiber's live state.
public struct EntryRow: Sendable, Identifiable, Hashable {
  public let id: String
  public let plugin: String
  public let parent: String?
  public let depth: Int
  public let isGroup: Bool
  public let state: EntryState
  public let dependencies: [Dependency]
  /// Service the entry provides, if any.
  public let provides: String?
  /// Isolation declared on the entry, e.g. `theme → private realm`.
  public let isolation: [String]
  /// The entry's persisted config, pretty-printed JSON ("" when none).
  public let config: String
  public let effects: [EffectLine]
  public let error: String?

  public var missing: [String] { dependencies.filter { $0.available == false }.map(\.name) }
}

/// A provided service and the realm it lives in.
public struct ServiceRow: Sendable, Identifiable, Hashable {
  public var id: String { "\(realm)/\(name)/\(provider)" }
  public let name: String
  public let realm: String
  public let provider: String
  public let state: EntryState
  /// Entries that inject this service and resolve it to this provider's realm.
  public let consumers: [String]
}

/// One line of the timeline.
public struct TimelineEvent: Sendable, Identifiable, Hashable {
  public enum Kind: String, Sendable, CaseIterable {
    case action, status, service, plugin, info, warn, error, debug
  }

  public let id: Int
  public let date: Date
  public let kind: Kind
  public let text: String
}

/// Everything the UI renders, captured on `CordisActor`.
public struct ShowcaseSnapshot: Sendable {
  public let revision: Int
  public let entries: [EntryRow]
  public let cards: [Card]
  public let services: [ServiceRow]
  public let timeline: [TimelineEvent]

  public static let empty = ShowcaseSnapshot(revision: 0, entries: [], cards: [], services: [], timeline: [])

  public func row(_ id: String) -> EntryRow? {
    entries.first { $0.id == id }
  }
}

/// A change the user (or the tour) asks for.
public enum ShowcaseOperation: Sendable, Equatable, CustomStringConvertible {
  case setEnabled(String, Bool)
  case updateConfig(String, JSONValue?)
  case restart(String)
  case remove(String)
  /// Adds a top-level entry; a nil config uses the catalog default.
  case add(plugin: String, config: JSONValue?)
  /// Reconciles the tree back to `ShowcaseCatalog.defaultEntries`.
  case reset

  public var description: String {
    switch self {
    case .setEnabled(let id, let enabled): "\(enabled ? "enable" : "disable") \(id)"
    case .updateConfig(let id, let config): "update \(id) config to \(config.map(JSONText.compact) ?? "null")"
    case .restart(let id): "restart \(id)"
    case .remove(let id): "remove \(id)"
    case .add(let plugin, _): "add \(plugin)"
    case .reset: "reset to the default entries"
    }
  }
}

/// Outcome of a `ShowcaseOperation`: errors the system logged while it ran,
/// and the error it threw, if any.
public struct OperationResult: Sendable {
  public let errors: [String]
  public let thrown: String?
}

/// JSON text helpers for configs.
public enum JSONText {
  public struct ParseError: Error, CustomStringConvertible {
    public let description: String
  }

  public static func pretty(_ value: JSONValue) -> String {
    encode(value, [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
  }

  public static func compact(_ value: JSONValue) -> String {
    encode(value, [.sortedKeys, .withoutEscapingSlashes])
  }

  /// Parses config text; empty text is no config. Typographic double
  /// quotes, which the iOS keyboard inserts by default, read as straight ones.
  public static func parse(_ text: String) throws -> JSONValue? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "[“”„]", with: "\"", options: .regularExpression)
    if trimmed.isEmpty { return nil }
    do {
      return try JSONDecoder().decode(JSONValue.self, from: Data(trimmed.utf8))
    } catch {
      throw ParseError(description: "config is not valid JSON")
    }
  }

  private static func encode(_ value: JSONValue, _ formatting: JSONEncoder.OutputFormatting) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = formatting
    guard let data = try? encoder.encode(value) else { return "" }
    return String(decoding: data, as: UTF8.self)
  }
}
