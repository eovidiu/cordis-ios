import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct CordisMacrosPlugin: CompilerPlugin {
  let providingMacros: [Macro.Type] = [
    PluginMacro.self,
    ServiceMacro.self,
    InjectMacro.self,
  ]
}
