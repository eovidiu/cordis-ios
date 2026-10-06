import Cordis

/// Colour of a dashboard card; the app maps it to a SwiftUI colour.
public enum CardTint: String, Sendable, CaseIterable, Codable {
  case blue, orange, green, purple, pink, teal, indigo, gray, yellow, red, mint
}

/// A button on a dashboard card. `run` executes on `CordisActor`.
public struct CardAction: Sendable, Identifiable {
  public let id: String
  public let title: String
  public let systemImage: String
  let run: @CordisActor @Sendable () -> Void
}

/// What a plugin puts on the dashboard.
public struct CardContent: Sendable {
  public var title: String
  public var value: String
  public var detail: String
  public var systemImage: String
  public var tint: CardTint
  public var actions: [CardAction]

  init(title: String, value: String, detail: String = "", systemImage: String, tint: CardTint, actions: [CardAction] = []) {
    self.title = title
    self.value = value
    self.detail = detail
    self.systemImage = systemImage
    self.tint = tint
    self.actions = actions
  }
}

/// A card as shown by the app: the content plus the entry that contributed it.
public struct Card: Sendable, Identifiable {
  public let id: Int
  /// Loader entry id of the contributing plugin.
  public let owner: String
  /// Runtime name of the contributing plugin.
  public let plugin: String
  public let content: CardContent

  public var title: String { content.title }
  public var value: String { content.value }
  public var detail: String { content.detail }
  public var actions: [CardAction] { content.actions }
}

/// Service key of the dashboard the app itself provides on the root context.
public enum DashboardKey: ServiceKey {
  public typealias Value = DashboardService
  public static let name = "dashboard"
}

/// The host-provided service plugins draw on. A card is installed as an
/// effect of the contributing plugin's context, so the card disappears by
/// itself when that plugin unloads: plugins never remove their UI by hand.
@CordisActor
public final class DashboardService {
  struct Record {
    let id: Int
    let fiber: Fiber
    var content: CardContent
  }

  private(set) var records: [Record] = []
  private var counter = 0
  var onChange: (@CordisActor () -> Void)?

  public init() {}

  /// Adds `content` until `ctx`'s fiber unloads. Returns a handle for live updates.
  @discardableResult
  func contribute(from ctx: Context, _ content: CardContent) throws -> CardHandle {
    counter += 1
    let id = counter
    try ctx.effect("dashboard card \"\(content.title)\"", sync: { [self] in
      records.append(Record(id: id, fiber: ctx.fiber, content: content))
      onChange?()
      return { [weak self] in
        guard let self else { return }
        records.removeAll { $0.id == id }
        onChange?()
      }
    })
    return CardHandle(id: id, dashboard: self)
  }

  func update(_ id: Int, _ body: (inout CardContent) -> Void) {
    guard let index = records.firstIndex(where: { $0.id == id }) else { return }
    body(&records[index].content)
    onChange?()
  }
}

/// Updates one contributed card; a no-op once the card was removed.
@CordisActor
final class CardHandle {
  let id: Int
  private weak var dashboard: DashboardService?

  init(id: Int, dashboard: DashboardService) {
    self.id = id
    self.dashboard = dashboard
  }

  func update(_ body: (inout CardContent) -> Void) {
    dashboard?.update(id, body)
  }
}
