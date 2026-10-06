import Cordis
import Foundation

/// Plugins and driver of the `cordis-demo` executable.

/// Where the demo writes its lines (stdout by default; tests capture it).
@CordisActor public var demoOutput: (String) -> Void = { print($0) }

enum ClockKey: ServiceKey {
  typealias Value = ClockService
  static let name = "clock"
}

/// Provides the current time as service `clock`.
@CordisActor @Service(ClockKey.self)
final class ClockService {
  func now() -> Date { Date() }
}

struct GreeterConfig: Codable, Sendable {
  var name: String?
}

/// Runs only while `clock` is provided.
@CordisActor @Plugin
final class GreeterPlugin {
  typealias Config = GreeterConfig
  @Inject(ClockKey.self) var clock: ClockService

  func apply(_ scope: EffectScope) async throws {
    let time = ISO8601DateFormatter().string(from: try clock.now())
    demoOutput("greeter: active at \(time)")
    try scope.collect { demoOutput("greeter: disposed") }
  }
}

struct DemoError: Error, CustomStringConvertible {
  var description: String { "DemoError: noisy plugin refused to start" }
}

/// Always fails, to show the `failed` state.
@CordisActor @Plugin
final class NoisyPlugin {
  func apply(_ scope: EffectScope) async throws {
    throw DemoError()
  }
}

/// Starts a loader over `entriesURL`, then disables and re-enables `clock`,
/// printing the fiber state table after each step.
@CordisActor
public func runDemo(entriesURL: URL) async throws {
  let root = Context()
  try root.logger.exporter(ClosureExporter(level: .error) { message in
    demoOutput("[\(message.level)] \(message.name): \(message.text)")
  })

  var catalog = PluginCatalog()
  catalog.register(ClockService.self, as: "clock")
  catalog.register(GreeterPlugin.self, as: "greeter")
  catalog.register(NoisyPlugin.self, as: "noisy")
  let loader = Loader(ctx: root, catalog: catalog, store: FileEntryStore(url: entriesURL))

  func printTable() {
    for entry in loader.entries {
      let state = loader.fiber(for: entry.id)?.state.description ?? (entry.disabled ? "disposed" : "missing")
      demoOutput(entry.id.padding(toLength: 9, withPad: " ", startingAt: 0) + state)
    }
  }

  try await loader.start()
  printTable()
  demoOutput("--- disable clock")
  try await loader.setDisabled(id: "clock", true)
  printTable()
  demoOutput("--- enable clock")
  try await loader.setDisabled(id: "clock", false)
  printTable()
}

/// Copies the bundled `entries.json` to a writable temporary file.
public func writableEntries() throws -> URL {
  let source = Bundle.module.url(forResource: "entries", withExtension: "json")!
  let target = FileManager.default.temporaryDirectory
    .appendingPathComponent("cordis-demo-\(UUID().uuidString).json")
  try FileManager.default.copyItem(at: source, to: target)
  return target
}
