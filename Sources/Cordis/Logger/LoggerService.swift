import Foundation
#if canImport(os)
import os
#endif

public enum LogLevel: Int, Sendable, Comparable {
  case error = 0
  case warn = 1
  case info = 2
  case debug = 3

  public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct LogMessage: Sendable {
  public let name: String
  public let level: LogLevel
  public let text: String
  public let error: (any Error)?
  public let timestamp: Date
}

/// A log sink. `level` is the most verbose level it accepts; nil defers to
/// the logger's level (`LoggerIntercept.Config.level`, default `.info`).
public protocol LogExporter: Sendable {
  var level: LogLevel? { get }
  @CordisActor func export(_ message: LogMessage)
}

/// Exporter backed by a closure.
public struct ClosureExporter: LogExporter {
  public let level: LogLevel?
  private let body: @CordisActor @Sendable (LogMessage) -> Void

  public init(level: LogLevel? = nil, _ body: @escaping @CordisActor @Sendable (LogMessage) -> Void) {
    self.level = level
    self.body = body
  }

  public func export(_ message: LogMessage) {
    body(message)
  }
}

#if canImport(os)
/// Default exporter: unified logging, subsystem `cordis`, category = logger name.
public struct OSLogExporter: LogExporter {
  public let level: LogLevel?

  public init(level: LogLevel? = nil) {
    self.level = level
  }

  public func export(_ message: LogMessage) {
    let logger = os.Logger(subsystem: "cordis", category: message.name)
    switch message.level {
    case .error: logger.error("\(message.text, privacy: .public)")
    case .warn: logger.warning("\(message.text, privacy: .public)")
    case .info: logger.info("\(message.text, privacy: .public)")
    case .debug: logger.debug("\(message.text, privacy: .public)")
    }
  }
}
#endif

/// Default exporter where `os` is unavailable: prints to standard output.
public struct PrintExporter: LogExporter {
  public let level: LogLevel?

  public init(level: LogLevel? = nil) {
    self.level = level
  }

  public func export(_ message: LogMessage) {
    print("[\(message.level)] \(message.name): \(message.text)")
  }
}

/// Interception key for loggers: `ctx.intercept(LoggerIntercept.self, .init(name: "x"))`.
public enum LoggerIntercept: InterceptKey {
  public struct Config: Sendable {
    public var name: String?
    public var level: LogLevel?

    public init(name: String? = nil, level: LogLevel? = nil) {
      self.name = name
      self.level = level
    }
  }

  public static let name = "logger"
}

/// Root logging state (minimal port of cordis `logger.ts`: no printf
/// formatting, no colors). Messages at the logger's level or above are kept
/// in `buffer`, bounded by `bufferSize`, oldest dropped first.
@CordisActor
public final class LoggerService {
  public var bufferSize = 100 {
    didSet { trim() }
  }

  public private(set) var buffer: [LogMessage] = []
  private var exporters: [UInt64: any LogExporter] = [:]
  private var counter: UInt64 = 0

  init() {}

  func installDefaultExporter(on ctx: Context) {
    #if canImport(os)
    _ = try? addExporter(OSLogExporter(), on: ctx)
    #else
    _ = try? addExporter(PrintExporter(), on: ctx)
    #endif
  }

  func addExporter(_ exporter: any LogExporter, on ctx: Context) throws -> EffectHandle {
    try ctx.effect("ctx.logger.exporter()", sync: { [self] in
      counter += 1
      let id = counter
      exporters[id] = exporter
      return { [self] in exporters[id] = nil }
    })
  }

  func log(name: String, level: LogLevel, loggerLevel: LogLevel?, text: String, error: (any Error)?) {
    let message = LogMessage(name: name, level: level, text: text, error: error, timestamp: Date())
    if level <= loggerLevel ?? .info {
      buffer.append(message)
      trim()
    }
    for id in exporters.keys.sorted() {
      guard let exporter = exporters[id] else { continue }
      if level > exporter.level ?? loggerLevel ?? .info { continue }
      exporter.export(message)
    }
  }

  private func trim() {
    let overflow = buffer.count - max(bufferSize, 0)
    if overflow > 0 { buffer.removeFirst(overflow) }
  }
}

/// A logger bound to a context. Its name is, in order: an explicit name
/// (`named(_:)`), the nearest `LoggerIntercept` name, the context's fiber name.
@CordisActor
public struct Logger {
  let ctx: Context
  let explicitName: String?

  var service: LoggerService { ctx.loggerService }

  public var name: String {
    explicitName ?? ctx.interceptConfig(LoggerIntercept.self)?.name ?? ctx.fiber.name
  }

  public func named(_ name: String) -> Logger {
    Logger(ctx: ctx, explicitName: name)
  }

  public var buffer: [LogMessage] { service.buffer }

  public var bufferSize: Int {
    get { service.bufferSize }
    nonmutating set { service.bufferSize = newValue }
  }

  /// Adds an exporter as an effect of this context's fiber.
  @discardableResult
  public func exporter(_ exporter: any LogExporter) throws -> EffectHandle {
    try service.addExporter(exporter, on: ctx)
  }

  public func error(_ text: String) { log(.error, text, nil) }
  public func warn(_ text: String) { log(.warn, text, nil) }
  public func info(_ text: String) { log(.info, text, nil) }
  public func debug(_ text: String) { log(.debug, text, nil) }

  /// Logs an error; an `AggregateError` logs each of its errors.
  public func error(_ error: any Error) {
    if let aggregate = error as? AggregateError {
      for inner in aggregate.errors { self.error(inner) }
      return
    }
    log(.error, String(describing: error), error)
  }

  private func log(_ level: LogLevel, _ text: String, _ error: (any Error)?) {
    service.log(
      name: name,
      level: level,
      loggerLevel: ctx.interceptConfig(LoggerIntercept.self)?.level,
      text: text,
      error: error
    )
  }
}
