import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

enum CordisMacroDiagnostic: String, DiagnosticMessage {
  case pluginRequiresFinalClass
  case serviceRequiresFinalClass
  case generatedMemberExists
  case requiresCordisActor
  case injectForm

  var message: String {
    switch self {
    case .pluginRequiresFinalClass: "@Plugin can only be applied to a final class"
    case .serviceRequiresFinalClass: "@Service can only be applied to a final class"
    case .requiresCordisActor: "@Plugin and @Service classes must be marked @CordisActor"
    case .generatedMemberExists: "@Plugin generates 'ctx'/'config'; remove the existing declaration"
    case .injectForm: "@Inject requires a 'var' with a type annotation and no initializer inside a @Plugin class"
    }
  }

  var diagnosticID: MessageID { MessageID(domain: "CordisMacros", id: rawValue) }
  var severity: DiagnosticSeverity { .error }
}

/// Shared expansion of `@Plugin` and `@Service(Key.self)`.
enum PluginExpansion {
  static func attributeName(_ attribute: AttributeSyntax) -> String {
    attribute.attributeName.trimmedDescription
  }

  static func hasAttribute(_ attributes: AttributeListSyntax, named names: Set<String>) -> Bool {
    attributes.contains { element in
      guard case .attribute(let attribute) = element else { return false }
      return names.contains(attributeName(attribute))
    }
  }

  /// The final class the macro is attached to, or nil after diagnosing.
  static func finalClass(
    _ declaration: some DeclGroupSyntax,
    node: AttributeSyntax,
    context: some MacroExpansionContext,
    error: CordisMacroDiagnostic
  ) -> ClassDeclSyntax? {
    guard let classDecl = declaration.as(ClassDeclSyntax.self),
          classDecl.modifiers.contains(where: { $0.name.tokenKind == .keyword(.final) })
    else {
      context.diagnose(Diagnostic(node: node, message: error))
      return nil
    }
    guard hasAttribute(classDecl.attributes, named: ["CordisActor", "Cordis.CordisActor"]) else {
      context.diagnose(Diagnostic(node: node, message: CordisMacroDiagnostic.requiresCordisActor))
      return nil
    }
    return classDecl
  }

  /// Key expressions of `@Inject(Key.self)` properties, in source order.
  static func injectKeys(_ classDecl: ClassDeclSyntax) -> [String] {
    classDecl.memberBlock.members.compactMap { member in
      guard let variable = member.decl.as(VariableDeclSyntax.self) else { return nil }
      for element in variable.attributes {
        guard case .attribute(let attribute) = element, attributeName(attribute) == "Inject",
              case .argumentList(let arguments) = attribute.arguments,
              let first = arguments.first
        else { continue }
        return first.expression.trimmedDescription
      }
      return nil
    }
  }

  static func members(
    of classDecl: ClassDeclSyntax,
    node: AttributeSyntax,
    context: some MacroExpansionContext
  ) -> [DeclSyntax]? {
    var hasConfigAlias = false
    var conflict = false
    for member in classDecl.memberBlock.members {
      if let alias = member.decl.as(TypeAliasDeclSyntax.self), alias.name.text == "Config" {
        hasConfigAlias = true
      }
      if let variable = member.decl.as(VariableDeclSyntax.self) {
        for binding in variable.bindings {
          if let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
             name == "ctx" || name == "config" {
            context.diagnose(Diagnostic(node: variable, message: CordisMacroDiagnostic.generatedMemberExists))
            conflict = true
          }
        }
      }
    }
    if conflict { return nil }
    let configType = hasConfigAlias ? "Config" : "NoConfig"
    let keys = injectKeys(classDecl)
    return [
      "public let ctx: Context",
      "public let config: \(raw: configType)",
      """
      public init(ctx: Context, config: \(raw: configType)) {
        self.ctx = ctx
        self.config = config
      }
      """,
      "public nonisolated static var inject: [any ServiceKey.Type] { [\(raw: keys.joined(separator: ", "))] }",
    ]
  }
}

/// `@Plugin`: generates `ctx`, `config`, `init(ctx:config:)` and `inject`
/// (from the `@Inject` properties), and adds the `Plugin` conformance.
public struct PluginMacro: MemberMacro, ExtensionMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingMembersOf declaration: some DeclGroupSyntax,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    guard let classDecl = PluginExpansion.finalClass(declaration, node: node, context: context, error: .pluginRequiresFinalClass) else {
      return []
    }
    return PluginExpansion.members(of: classDecl, node: node, context: context) ?? []
  }

  public static func expansion(
    of node: AttributeSyntax,
    attachedTo declaration: some DeclGroupSyntax,
    providingExtensionsOf type: some TypeSyntaxProtocol,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [ExtensionDeclSyntax] {
    guard declaration.is(ClassDeclSyntax.self) else { return [] }
    return [try ExtensionDeclSyntax("extension \(type.trimmed): Cordis.Plugin {}")]
  }
}

/// `@Service(Key.self)`: like `@Plugin`, plus `typealias Key` and the
/// `ServicePlugin` conformance.
public struct ServiceMacro: MemberMacro, ExtensionMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingMembersOf declaration: some DeclGroupSyntax,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    guard let classDecl = PluginExpansion.finalClass(declaration, node: node, context: context, error: .serviceRequiresFinalClass),
          var members = PluginExpansion.members(of: classDecl, node: node, context: context)
    else { return [] }
    if case .argumentList(let arguments) = node.arguments, let key = arguments.first?.expression.as(MemberAccessExprSyntax.self)?.base {
      members.insert("public typealias Key = \(raw: key.trimmedDescription)", at: 0)
    }
    return members
  }

  public static func expansion(
    of node: AttributeSyntax,
    attachedTo declaration: some DeclGroupSyntax,
    providingExtensionsOf type: some TypeSyntaxProtocol,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [ExtensionDeclSyntax] {
    guard declaration.is(ClassDeclSyntax.self) else { return [] }
    return [try ExtensionDeclSyntax("extension \(type.trimmed): Cordis.ServicePlugin {}")]
  }
}

/// `@Inject(Key.self) var name: Type`: a throwing getter reading the
/// injected service through `ctx[Key.self]`.
public struct InjectMacro: AccessorMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingAccessorsOf declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext
  ) throws -> [AccessorDeclSyntax] {
    guard let variable = declaration.as(VariableDeclSyntax.self),
          variable.bindingSpecifier.tokenKind == .keyword(.var),
          let binding = variable.bindings.first,
          variable.bindings.count == 1,
          binding.typeAnnotation != nil,
          binding.initializer == nil,
          binding.accessorBlock == nil,
          isInsidePluginClass(context),
          case .argumentList(let arguments) = node.arguments,
          let key = arguments.first?.expression
    else {
      context.diagnose(Diagnostic(node: node, message: CordisMacroDiagnostic.injectForm))
      return []
    }
    return [
      """
      get throws {
        try ctx[\(key.trimmed)]
      }
      """,
    ]
  }

  private static func isInsidePluginClass(_ context: some MacroExpansionContext) -> Bool {
    guard let classDecl = context.lexicalContext.first?.as(ClassDeclSyntax.self) else { return false }
    return PluginExpansion.hasAttribute(classDecl.attributes, named: ["Plugin", "Service", "Cordis.Plugin", "Cordis.Service"])
  }
}
