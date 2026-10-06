import Foundation
import Testing
@testable import Cordis
@testable import CordisDemoKit

@Suite("DemoTests")
@CordisActor
struct DemoTests {
  @Test("demo prints the state tables")
  func demoPrintsStateTables() async throws {
    let lines = Recorder<String>()
    demoOutput = { lines.record($0) }
    defer { demoOutput = { print($0) } }
    let url = try writableEntries()
    defer { try? FileManager.default.removeItem(at: url) }

    try await runDemo(entriesURL: url)

    let tables = lines.calls.filter { !$0.hasPrefix("greeter:") && !$0.hasPrefix("[") }
    #expect(tables == [
      "clock    active",
      "greeter  active",
      "noisy    failed",
      "--- disable clock",
      "clock    disposed",
      "greeter  pending",
      "noisy    failed",
      "--- enable clock",
      "clock    active",
      "greeter  active",
      "noisy    failed",
    ])
    #expect(lines.calls.filter { $0.hasPrefix("greeter: active at ") }.count == 2)
    #expect(lines.calls.filter { $0 == "greeter: disposed" }.count == 1)
    #expect(lines.calls.filter { $0.hasPrefix("[error]") } == ["[error] NoisyPlugin: DemoError: noisy plugin refused to start"])

    let saved = try JSONDecoder().decode([Entry].self, from: Data(contentsOf: url))
    #expect(saved.map(\.disabled) == [false, false, false])
  }
}
