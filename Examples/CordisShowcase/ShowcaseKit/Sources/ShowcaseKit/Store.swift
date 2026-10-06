import Cordis
import Foundation
import Observation

/// Main-actor mirror of the engine for SwiftUI. Views read `snapshot` and
/// call the async operations; the engine pushes a fresh snapshot after
/// every change.
@MainActor @Observable
public final class ShowcaseStore {
  public private(set) var snapshot: ShowcaseSnapshot = .empty
  /// Operations in flight.
  public private(set) var busy = 0
  /// The last operation's problems, for an alert.
  public var problem: Problem?

  public struct Problem: Identifiable, Sendable {
    public let id = UUID()
    public let title: String
    public let message: String
  }

  @ObservationIgnored public let engine: ShowcaseEngine

  public init(engine: ShowcaseEngine) {
    self.engine = engine
  }

  /// A store over entries persisted in Application Support, seeded with the
  /// default entries on first launch.
  public static func live() async -> ShowcaseStore {
    let store = FileEntryStore(url: Self.entriesURL)
    if !FileManager.default.fileExists(atPath: Self.entriesURL.path) {
      try? FileManager.default.createDirectory(at: Self.entriesURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try? await store.save(ShowcaseCatalog.defaultEntries)
    }
    let engine = await ShowcaseEngine(store: store)
    return ShowcaseStore(engine: engine)
  }

  public static var entriesURL: URL {
    URL.applicationSupportDirectory.appendingPathComponent("CordisShowcase/entries.json")
  }

  public func start() async {
    let handler: @Sendable (ShowcaseSnapshot) -> Void = { [weak self] snapshot in
      Task { @MainActor in self?.apply(snapshot) }
    }
    let engine = engine
    do {
      try await Task { @CordisActor in
        engine.onSnapshot = handler
        try await engine.start()
      }.value
    } catch {
      problem = Problem(title: "Could not start", message: String(describing: error))
    }
  }

  private func apply(_ snapshot: ShowcaseSnapshot) {
    if snapshot.revision > self.snapshot.revision { self.snapshot = snapshot }
  }

  public var isBusy: Bool { busy > 0 }

  /// Runs `operation`; problems end up in `problem`.
  public func run(_ operation: ShowcaseOperation) async {
    busy += 1
    defer { busy -= 1 }
    let result = await engine.run(operation)
    if let thrown = result.thrown {
      problem = Problem(title: "\(operation.description.capitalizedFirst) failed", message: thrown)
    } else if !result.errors.isEmpty {
      problem = Problem(title: "Cordis logged an error", message: result.errors.joined(separator: "\n\n"))
    }
  }

  /// Parses `text` as JSON and updates entry `id`'s config.
  public func updateConfig(_ id: String, text: String) async {
    do {
      await run(.updateConfig(id, try JSONText.parse(text)))
    } catch {
      problem = Problem(title: "Invalid JSON", message: String(describing: error))
    }
  }

  public func trigger(_ action: CardAction) {
    let engine = engine
    Task { await engine.trigger(action) }
  }
}

extension String {
  var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
