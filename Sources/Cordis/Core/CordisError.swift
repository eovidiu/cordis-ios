/// Errors raised by the cordis core. Messages are cordis's strings verbatim.
public struct CordisError: Error, CustomStringConvertible, Sendable {
  public enum Code: String, Sendable {
    case inactiveEffect = "INACTIVE_EFFECT"
    case inactiveContext = "INACTIVE_CONTEXT"
    case invalidPlugin = "INVALID_PLUGIN"
    case duplicateService = "DUPLICATE_SERVICE"
    case propertyTypeMismatch = "PROPERTY_TYPE"
    case missingInject = "MISSING_INJECT"
    case inactiveService = "INACTIVE_SERVICE"
    case setWithoutProvide = "SET_WITHOUT_PROVIDE"
    case setInOtherFiber = "SET_IN_OTHER_FIBER"
    case nextCalledMultipleTimes = "NEXT_CALLED_MULTIPLE_TIMES"
    case invalidEffect = "INVALID_EFFECT"
  }

  public let code: Code
  public let message: String

  public init(_ code: Code, _ message: String) {
    self.code = code
    self.message = message
  }

  public var description: String { message }

  static let inactiveEffect = CordisError(.inactiveEffect, "cannot create effect on inactive context")
  static let nextCalledMultipleTimes = CordisError(.nextCalledMultipleTimes, "next() called multiple times")

  static func duplicateService(_ name: String, at fiberName: String) -> CordisError {
    CordisError(.duplicateService, "service \"\(name)\" has been registered at <\(fiberName)>")
  }

  static func propertyType(_ name: String, _ type: String) -> CordisError {
    CordisError(.propertyTypeMismatch, "property \"\(name)\" is already declared as \(type)")
  }

  static func missingInject(_ name: String) -> CordisError {
    CordisError(.missingInject, "cannot get property \"\(name)\" without inject")
  }

  static func inactiveService(_ name: String) -> CordisError {
    CordisError(.inactiveService, "cannot get required service \"\(name)\" in inactive context")
  }

  static func setWithoutProvide(_ name: String) -> CordisError {
    CordisError(.setWithoutProvide, "cannot set property \"\(name)\" without provide")
  }

  static func setInOtherFiber(_ name: String) -> CordisError {
    CordisError(.setInOtherFiber, "cannot set property \"\(name)\" in multiple fibers")
  }
}

/// One problem found while validating a plugin config.
public struct ValidationIssue: Sendable, Equatable {
  public let message: String
  public let path: [String]

  public init(message: String, path: [String] = []) {
    self.message = message
    self.path = path
  }
}

/// A config failed decoding or `Plugin.validate`. The description matches
/// cordis's `ValidationError` format.
public struct ValidationError: Error, CustomStringConvertible, Sendable {
  public let issues: [ValidationIssue]

  public init(issues: [ValidationIssue]) {
    self.issues = issues
  }

  public var description: String {
    "invalid config:\n" + issues.map { issue in
      issue.path.isEmpty ? "  - \(issue.message)" : "  - \(issue.message) (at \(issue.path.joined(separator: ".")))"
    }.joined(separator: "\n")
  }
}

/// Thrown by `EffectScope.collect` once the effect (or the plugin run) it
/// belongs to was disposed. Effect runners treat it as normal completion,
/// mirroring cordis's generator runner, which stops iterating on abort.
public struct EffectAbortedError: Error, Sendable {
  public init() {}
}

/// Several listeners or disposers failed (`ctx.parallel`).
public struct AggregateError: Error, CustomStringConvertible, Sendable {
  public let errors: [any Error]

  public init(errors: [any Error]) {
    self.errors = errors
  }

  public var description: String {
    "AggregateError: " + errors.map { String(describing: $0) }.joined(separator: "; ")
  }
}
