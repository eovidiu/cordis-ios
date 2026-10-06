import Cordis

/// Catalog metadata the app shows when adding a plugin.
public struct PluginInfo: Sendable, Identifiable, Equatable {
  public var id: String { name }
  public let name: String
  public let summary: String
  public let systemImage: String
  /// Service this plugin provides, if it is a service.
  public let provides: String?
  /// Services the plugin injects (its `inject` list).
  public let injects: [String]
  /// Config used for a new entry.
  public let defaultConfig: JSONValue?
}

/// The showcase's plugins, by catalog name.
public enum ShowcaseCatalog {
  static func make() -> PluginCatalog {
    var catalog = PluginCatalog()
    catalog.register(ClockService.self, as: "clock")
    catalog.register(ClockCardPlugin.self, as: "clock-card")
    catalog.register(GreeterPlugin.self, as: "greeter")
    catalog.register(CounterService.self, as: "counter")
    catalog.register(CounterCardPlugin.self, as: "counter-card")
    catalog.register(NetworkService.self, as: "network")
    catalog.register(WeatherPlugin.self, as: "weather")
    catalog.register(FlakyPlugin.self, as: "flaky")
    catalog.register(ThemeService.self, as: "theme")
    catalog.register(ThemeCardPlugin.self, as: "theme-card")
    catalog.register(AuditPlugin.self, as: "audit")
    return catalog
  }

  private static func names(_ keys: [any ServiceKey.Type]) -> [String] {
    keys.map { $0.name }
  }

  public static let plugins: [PluginInfo] = [
    PluginInfo(
      name: "clock", summary: "Service that ticks every interval and emits showcase/tick.",
      systemImage: "clock", provides: ClockKey.name, injects: names(ClockService.inject),
      defaultConfig: .object(["interval": .number(1)])),
    PluginInfo(
      name: "clock-card", summary: "Dashboard card that re-renders on every tick.",
      systemImage: "clock.badge", provides: nil, injects: names(ClockCardPlugin.inject), defaultConfig: nil),
    PluginInfo(
      name: "greeter", summary: "Greets config.name; rejects an empty name.",
      systemImage: "hand.wave", provides: nil, injects: names(GreeterPlugin.inject),
      defaultConfig: .object(["name": .string("World")])),
    PluginInfo(
      name: "counter", summary: "Service holding an integer; restarting it resets the value.",
      systemImage: "number", provides: CounterKey.name, injects: names(CounterService.inject), defaultConfig: nil),
    PluginInfo(
      name: "counter-card", summary: "Card with buttons that call the counter service.",
      systemImage: "plusminus", provides: nil, injects: names(CounterCardPlugin.inject), defaultConfig: nil),
    PluginInfo(
      name: "network", summary: "Simulated backend with a configurable latency.",
      systemImage: "network", provides: NetworkKey.name, injects: names(NetworkService.inject),
      defaultConfig: .object(["latency": .number(1.2)])),
    PluginInfo(
      name: "weather", summary: "Fetches a forecast through the network service while loading.",
      systemImage: "cloud.sun", provides: nil, injects: names(WeatherPlugin.inject),
      defaultConfig: .object(["city": .string("Bucharest")])),
    PluginInfo(
      name: "flaky", summary: "Throws from apply until config.fail is false.",
      systemImage: "exclamationmark.triangle", provides: nil, injects: names(FlakyPlugin.inject),
      defaultConfig: .object(["fail": .bool(true)])),
    PluginInfo(
      name: "theme", summary: "Service with a name and a tint; isolate it to run several.",
      systemImage: "paintpalette", provides: ThemeKey.name, injects: names(ThemeService.inject),
      defaultConfig: .object(["name": .string("Custom"), "tint": .string("mint")])),
    PluginInfo(
      name: "theme-card", summary: "Card showing the theme resolved in its realm.",
      systemImage: "swatchpalette", provides: nil, injects: names(ThemeCardPlugin.inject), defaultConfig: nil),
    PluginInfo(
      name: "audit", summary: "Counts every fiber status transition.",
      systemImage: "list.bullet.clipboard", provides: nil, injects: names(AuditPlugin.inject), defaultConfig: nil),
  ]

  public static func info(_ name: String) -> PluginInfo? {
    plugins.first { $0.name == name }
  }

  /// The entry tree a fresh install starts with.
  public static let defaultEntries: [Entry] = [
    Entry(id: "clock", plugin: "clock", config: .object(["interval": .number(1)])),
    Entry(id: "clock-card", plugin: "clock-card"),
    Entry(id: "greeter", plugin: "greeter", config: .object(["name": .string("Ovidiu"), "emoji": .string("👋")])),
    Entry(id: "counter", plugin: "counter"),
    Entry(id: "counter-card", plugin: "counter-card"),
    Entry(id: "weather", plugin: "weather", config: .object(["city": .string("Bucharest")])),
    Entry(id: "flaky", plugin: "flaky", config: .object(["fail": .bool(true)])),
    Entry(id: "theme", plugin: "theme", config: .object(["name": .string("Day"), "tint": .string("orange")])),
    Entry(id: "theme-card", plugin: "theme-card"),
    Entry(id: "night", plugin: "group", isolate: ["theme": .local], children: [
      Entry(id: "night-theme", plugin: "theme", config: .object(["name": .string("Night"), "tint": .string("indigo")])),
      Entry(id: "night-card", plugin: "theme-card"),
    ]),
    Entry(id: "audit", plugin: "audit"),
  ]

  /// Whether service `name` is usable from `ctx` (in `ctx`'s realm).
  @CordisActor
  static func isAvailable(_ name: String, in ctx: Context) -> Bool {
    switch name {
    case DashboardKey.name: ctx.get(DashboardKey.self) != nil
    case ClockKey.name: ctx.get(ClockKey.self) != nil
    case CounterKey.name: ctx.get(CounterKey.self) != nil
    case NetworkKey.name: ctx.get(NetworkKey.self) != nil
    case ThemeKey.name: ctx.get(ThemeKey.self) != nil
    default: false
    }
  }
}
