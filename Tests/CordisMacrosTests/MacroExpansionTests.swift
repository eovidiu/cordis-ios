import CordisMacros
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing

private let macros: [String: MacroSpec] = [
  "Plugin": MacroSpec(type: PluginMacro.self, conformances: ["Plugin"]),
  "Service": MacroSpec(type: ServiceMacro.self, conformances: ["ServicePlugin"]),
  "Inject": MacroSpec(type: InjectMacro.self),
]

private func assertExpansion(
  _ source: String,
  expandedSource: String,
  diagnostics: [DiagnosticSpec] = [],
  sourceLocation: SourceLocation = #_sourceLocation
) {
  assertMacroExpansion(
    source,
    expandedSource: expandedSource,
    diagnostics: diagnostics,
    macroSpecs: macros,
    indentationWidth: .spaces(2),
    failureHandler: { failure in
      Issue.record(Comment(rawValue: failure.message), sourceLocation: sourceLocation)
    }
  )
}

@Suite("MacroExpansionTests")
struct MacroExpansionTests {
  @Test("plugin with two injected services")
  func pluginWithTwoInjections() {
    assertExpansion(
      """
      @CordisActor @Plugin
      final class Greeter {
        typealias Config = GreeterConfig
        @Inject(ClockKey.self) var clock: ClockService
        @Inject(LocationKey.self) var location: LocationService
      }
      """,
      expandedSource: """
      @CordisActor
      final class Greeter {
        typealias Config = GreeterConfig
        var clock: ClockService {
          get throws {
            try ctx[ClockKey.self]
          }
        }
        var location: LocationService {
          get throws {
            try ctx[LocationKey.self]
          }
        }

        public let ctx: Context

        public let config: Config

        public init(ctx: Context, config: Config) {
          self.ctx = ctx
          self.config = config
        }

        public nonisolated static var inject: [any ServiceKey.Type] {
          [ClockKey.self, LocationKey.self]
        }
      }

      extension Greeter: Cordis.Plugin {
      }
      """
    )
  }

  @Test("plugin without injected services")
  func pluginWithoutInjections() {
    assertExpansion(
      """
      @CordisActor @Service(ClockKey.self)
      final class ClockService {
      }
      """,
      expandedSource: """
      @CordisActor
      final class ClockService {

        public typealias Key = ClockKey

        public let ctx: Context

        public let config: NoConfig

        public init(ctx: Context, config: NoConfig) {
          self.ctx = ctx
          self.config = config
        }

        public nonisolated static var inject: [any ServiceKey.Type] {
          []
        }
      }

      extension ClockService: Cordis.ServicePlugin {
      }
      """
    )
  }

  @Test("diagnoses @Plugin on a non-final class")
  func diagnosesNonFinalClass() {
    assertExpansion(
      """
      @CordisActor @Plugin
      class Greeter {
      }
      """,
      expandedSource: """
      @CordisActor
      class Greeter {
      }

      extension Greeter: Cordis.Plugin {
      }
      """,
      diagnostics: [DiagnosticSpec(message: "@Plugin can only be applied to a final class", line: 1, column: 14)]
    )
  }

  @Test("diagnoses an existing ctx or config")
  func diagnosesExistingMember() {
    assertExpansion(
      """
      @CordisActor @Plugin
      final class Greeter {
        let ctx: Context
      }
      """,
      expandedSource: """
      @CordisActor
      final class Greeter {
        let ctx: Context
      }

      extension Greeter: Cordis.Plugin {
      }
      """,
      diagnostics: [DiagnosticSpec(message: "@Plugin generates 'ctx'/'config'; remove the existing declaration", line: 3, column: 3)]
    )
  }

  @Test("diagnoses a malformed @Inject")
  func diagnosesMalformedInject() {
    assertExpansion(
      """
      final class Plain {
        @Inject(ClockKey.self) var clock: ClockService
      }
      """,
      expandedSource: """
      final class Plain {
        var clock: ClockService
      }
      """,
      diagnostics: [
        DiagnosticSpec(
          message: "@Inject requires a 'var' with a type annotation and no initializer inside a @Plugin class",
          line: 2,
          column: 3
        ),
      ]
    )
  }

  @Test("diagnoses a class without @CordisActor")
  func diagnosesMissingActor() {
    assertExpansion(
      """
      @Plugin
      final class Greeter {
      }
      """,
      expandedSource: """
      final class Greeter {
      }

      extension Greeter: Cordis.Plugin {
      }
      """,
      diagnostics: [DiagnosticSpec(message: "@Plugin and @Service classes must be marked @CordisActor", line: 1, column: 1)]
    )
  }
}
