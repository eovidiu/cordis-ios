import Cordis
import Foundation

// MARK: - keys and events

enum ClockKey: ServiceKey {
  typealias Value = ClockService
  static let name = "clock"
}

enum CounterKey: ServiceKey {
  typealias Value = CounterService
  static let name = "counter"
}

enum NetworkKey: ServiceKey {
  typealias Value = NetworkService
  static let name = "network"
}

enum ThemeKey: ServiceKey {
  typealias Value = ThemeService
  static let name = "theme"
}

/// Emitted by the clock service on every tick.
enum TickEvent: EventKey {
  typealias Args = Date
  typealias Result = Never
  static let name = "showcase/tick"
}

/// Emitted by the counter service whenever its value changes.
enum CounterChangedEvent: EventKey {
  typealias Args = Int
  typealias Result = Never
  static let name = "showcase/counter-changed"
}

/// The realm `ctx` resolves service `name` in, as shown in the UI: "root"
/// for the realm every non-isolated context shares.
@CordisActor
func realmLabel(_ name: String, in ctx: Context) -> String {
  guard let realm = ctx.realm(of: name), realm != ctx.root.realm(of: name) else { return "root" }
  return realm.name
}

private func invalid(_ message: String, at path: String) -> ValidationError {
  ValidationError(issues: [ValidationIssue(message: message, path: [path])])
}

// MARK: - services

struct ClockConfig: Codable, Sendable {
  var interval: Double?
}

/// Service `clock`: emits `TickEvent` every `interval` seconds while loaded.
@CordisActor @Service(ClockKey.self)
final class ClockService {
  typealias Config = ClockConfig
  private(set) var ticks = 0

  nonisolated static func validate(_ config: ClockConfig) throws {
    if let interval = config.interval, interval < 0.05 {
      throw invalid("interval must be at least 0.05 seconds", at: "interval")
    }
  }

  func now() -> Date { Date() }

  func setup(_ scope: EffectScope) async throws {
    let interval = config.interval ?? 1
    let ctx = ctx
    let timer = Task { @CordisActor [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(interval))
        guard let self, !Task.isCancelled else { return }
        ticks += 1
        try? ctx.emit(TickEvent.self, Date())
      }
    }
    try scope.collect { timer.cancel() }
  }
}

/// Service `counter`: an integer that lives as long as the service instance.
@CordisActor @Service(CounterKey.self)
final class CounterService {
  private(set) var value = 0

  func add(_ delta: Int) {
    value += delta
    try? ctx.emit(CounterChangedEvent.self, value)
  }
}

struct NetworkConfig: Codable, Sendable {
  var latency: Double?
}

struct Forecast: Sendable {
  let temperature: Int
  let condition: String
  let symbol: String
}

/// Service `network`: a simulated slow backend.
@CordisActor @Service(NetworkKey.self)
final class NetworkService {
  typealias Config = NetworkConfig

  nonisolated static func validate(_ config: NetworkConfig) throws {
    if let latency = config.latency, latency < 0 || latency > 10 {
      throw invalid("latency must be between 0 and 10 seconds", at: "latency")
    }
  }

  func forecast(for city: String) async throws -> Forecast {
    try await Task.sleep(for: .seconds(config.latency ?? 1.2))
    let seed = city.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
    let conditions = [("Sunny", "sun.max"), ("Cloudy", "cloud"), ("Rain", "cloud.rain"), ("Windy", "wind")]
    let (condition, symbol) = conditions[seed % conditions.count]
    return Forecast(temperature: 8 + seed % 22, condition: condition, symbol: symbol)
  }
}

struct ThemeConfig: Codable, Sendable {
  var name: String?
  var tint: String?
}

/// Service `theme`: a named colour. Two providers can coexist in different realms.
@CordisActor @Service(ThemeKey.self)
final class ThemeService {
  typealias Config = ThemeConfig

  nonisolated static func validate(_ config: ThemeConfig) throws {
    if let tint = config.tint, CardTint(rawValue: tint) == nil {
      let names = CardTint.allCases.map(\.rawValue).joined(separator: ", ")
      throw invalid("tint must be one of \(names)", at: "tint")
    }
  }

  var displayName: String { config.name ?? "Default" }
  var tint: CardTint { config.tint.flatMap(CardTint.init(rawValue:)) ?? .gray }
}

// MARK: - plugins

/// Shows the time and re-renders on every `TickEvent`.
@CordisActor @Plugin
final class ClockCardPlugin {
  @Inject(DashboardKey.self) var dashboard: DashboardService
  @Inject(ClockKey.self) var clock: ClockService

  static func format(_ date: Date) -> String {
    date.formatted(date: .omitted, time: .standard)
  }

  func apply(_ scope: EffectScope) async throws {
    let clock = try clock
    let card = try dashboard.contribute(from: ctx, CardContent(
      title: "Clock", value: Self.format(clock.now()), detail: "\(clock.ticks) ticks from service \"clock\"",
      systemImage: "clock", tint: .blue
    ))
    try ctx.on(TickEvent.self) { date in
      card.update {
        $0.value = Self.format(date)
        $0.detail = "\(clock.ticks) ticks from service \"clock\""
      }
    }
  }
}

struct GreeterConfig: Codable, Sendable {
  var name: String?
  var emoji: String?
}

/// Greets `config.name`. Shows config validation and config-driven restarts.
@CordisActor @Plugin
final class GreeterPlugin {
  typealias Config = GreeterConfig
  @Inject(DashboardKey.self) var dashboard: DashboardService

  nonisolated static func validate(_ config: GreeterConfig) throws {
    if let name = config.name, name.trimmingCharacters(in: .whitespaces).isEmpty {
      throw invalid("name must not be empty", at: "name")
    }
  }

  func apply(_ scope: EffectScope) async throws {
    let name = config.name ?? "World"
    try dashboard.contribute(from: ctx, CardContent(
      title: "Greeter", value: "Hello, \(name) \(config.emoji ?? "👋")",
      detail: "Edit this entry's config to change the greeting",
      systemImage: "hand.wave", tint: .orange
    ))
  }
}

/// Renders service `counter` with buttons that call into the service.
@CordisActor @Plugin
final class CounterCardPlugin {
  @Inject(DashboardKey.self) var dashboard: DashboardService
  @Inject(CounterKey.self) var counter: CounterService

  func apply(_ scope: EffectScope) async throws {
    let counter = try counter
    let card = try dashboard.contribute(from: ctx, CardContent(
      title: "Counter", value: "\(counter.value)", detail: "State lives in service \"counter\"",
      systemImage: "number", tint: .green,
      actions: [
        CardAction(id: "decrement", title: "Decrement", systemImage: "minus") { counter.add(-1) },
        CardAction(id: "increment", title: "Increment", systemImage: "plus") { counter.add(1) },
      ]
    ))
    try ctx.on(CounterChangedEvent.self) { value in
      card.update { $0.value = "\(value)" }
    }
  }
}

struct WeatherConfig: Codable, Sendable {
  var city: String?
}

/// Needs service `network`, which the default entries do not provide: it
/// waits in `pending` until someone adds a network entry, then stays in
/// `loading` while the simulated request runs.
@CordisActor @Plugin
final class WeatherPlugin {
  typealias Config = WeatherConfig
  @Inject(DashboardKey.self) var dashboard: DashboardService
  @Inject(NetworkKey.self) var network: NetworkService

  func apply(_ scope: EffectScope) async throws {
    let city = config.city ?? "Bucharest"
    let forecast = try await network.forecast(for: city)
    try dashboard.contribute(from: ctx, CardContent(
      title: "Weather in \(city)", value: "\(forecast.temperature)°C", detail: forecast.condition,
      systemImage: forecast.symbol, tint: .teal
    ))
  }
}

struct FlakyConfig: Codable, Sendable {
  var fail: Bool?
}

struct FlakyError: Error, CustomStringConvertible {
  var description: String { "flaky refused to start (set \"fail\": false in its config)" }
}

/// Throws from `apply` until its config says otherwise: shows the `failed` state.
@CordisActor @Plugin
final class FlakyPlugin {
  typealias Config = FlakyConfig
  @Inject(DashboardKey.self) var dashboard: DashboardService

  func apply(_ scope: EffectScope) async throws {
    if config.fail ?? true { throw FlakyError() }
    try dashboard.contribute(from: ctx, CardContent(
      title: "Flaky", value: "Recovered", detail: "The config update cleared the failure",
      systemImage: "bandage", tint: .pink
    ))
  }
}

/// Renders whichever `theme` its context resolves; the realm decides which.
@CordisActor @Plugin
final class ThemeCardPlugin {
  @Inject(DashboardKey.self) var dashboard: DashboardService
  @Inject(ThemeKey.self) var theme: ThemeService

  func apply(_ scope: EffectScope) async throws {
    let theme = try theme
    let realm = realmLabel(ThemeKey.name, in: ctx)
    try dashboard.contribute(from: ctx, CardContent(
      title: "Theme", value: theme.displayName, detail: "Resolved in realm \"\(realm)\"",
      systemImage: "paintpalette", tint: theme.tint
    ))
  }
}

/// Listens to every fiber's status changes: plugins can observe the system.
@CordisActor @Plugin
final class AuditPlugin {
  @Inject(DashboardKey.self) var dashboard: DashboardService
  private var transitions = 0

  func apply(_ scope: EffectScope) async throws {
    let card = try dashboard.contribute(from: ctx, CardContent(
      title: "Audit", value: "0 transitions", detail: "Listening to internal/status",
      systemImage: "list.bullet.clipboard", tint: .purple
    ))
    try ctx.on(StatusEvent.self, options: EventOptions(global: true)) { [self] args in
      transitions += 1
      let count = transitions
      card.update {
        $0.value = "\(count) transition\(count == 1 ? "" : "s")"
        $0.detail = "Last: \(args.fiber.name) \(args.oldState) → \(args.fiber.state)"
      }
    }
  }
}
