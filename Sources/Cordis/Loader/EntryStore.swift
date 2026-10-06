import Foundation

/// Persistence for the loader's entry tree.
public protocol EntryStore: Sendable {
  @CordisActor func load() throws -> [Entry]
  @CordisActor func save(_ entries: [Entry]) throws
}

/// Entries as a pretty-printed JSON file, written atomically. A missing file
/// loads as no entries.
public struct FileEntryStore: EntryStore {
  public let url: URL

  public init(url: URL) {
    self.url = url
  }

  public func load() throws -> [Entry] {
    guard FileManager.default.fileExists(atPath: url.path) else { return [] }
    return try JSONDecoder().decode([Entry].self, from: Data(contentsOf: url))
  }

  public func save(_ entries: [Entry]) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(entries)
    let manager = FileManager.default
    let temp = url.deletingLastPathComponent()
      .appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
    try data.write(to: temp)
    if manager.fileExists(atPath: url.path) {
      _ = try manager.replaceItemAt(url, withItemAt: temp)
    } else {
      try manager.moveItem(at: temp, to: url)
    }
  }
}

/// Entries kept in memory (tests, previews).
@CordisActor
public final class InMemoryEntryStore: EntryStore {
  public private(set) var entries: [Entry]
  public private(set) var saveCount = 0

  public init(_ entries: [Entry] = []) {
    self.entries = entries
  }

  public func load() throws -> [Entry] {
    entries
  }

  public func save(_ entries: [Entry]) throws {
    self.entries = entries
    saveCount += 1
  }
}
