import Cordis

/// One step of the guided tour: an operation on the default entries, what
/// it demonstrates, and the entry states it leads to.
public struct TourStep: Sendable, Identifiable {
  public let id: Int
  public let title: String
  /// The cordis concept the step demonstrates.
  public let concept: String
  public let explanation: String
  /// What to look at after running the step.
  public let observe: String
  public let operations: [ShowcaseOperation]
  /// Entry states the step leads to (checked by the tests).
  public let expectedStates: [String: EntryState]?

  public static let all: [TourStep] = [
    TourStep(
      id: 1, title: "Withdraw a service", concept: "Dependency injection",
      explanation: "clock-card injects the clock service. Disabling the clock entry withdraws the service, so cordis unloads every plugin that injects it.",
      observe: "clock-card drops to pending and its card leaves the dashboard. Nobody removed the card by hand: it was an effect of clock-card's fiber.",
      operations: [.setEnabled("clock", false)],
      expectedStates: ["clock": .disabled, "clock-card": .pending]),
    TourStep(
      id: 2, title: "Provide it again", concept: "Reactive reload",
      explanation: "Re-enabling clock provides the service again. Pending consumers whose injects are all available load automatically.",
      observe: "clock-card returns to active and the clock card is back, ticking.",
      operations: [.setEnabled("clock", true)],
      expectedStates: ["clock": .active, "clock-card": .active]),
    TourStep(
      id: 3, title: "Change a config", concept: "Config updates",
      explanation: "Updating an entry's config calls fiber.update: the plugin is unloaded and reloaded with the new config. The loader persists the new config.",
      observe: "The greeter card now greets the world.",
      operations: [.updateConfig("greeter", .object(["name": .string("World"), "emoji": .string("🌍")]))],
      expectedStates: ["greeter": .active]),
    TourStep(
      id: 4, title: "Send an invalid config", concept: "Validation",
      explanation: "greeter's validate rejects an empty name. A config that fails validation never reaches the plugin; the running instance keeps its previous config.",
      observe: "An error appears in the timeline and the greeting does not change.",
      operations: [.updateConfig("greeter", .object(["name": .string("")]))],
      expectedStates: ["greeter": .active]),
    TourStep(
      id: 5, title: "Add a missing service", concept: "Pending → loading → active",
      explanation: "weather injects network, which no entry provides, so it has waited in pending since launch. Adding a network entry provides the service.",
      observe: "weather passes through loading while the simulated request runs (about a second), then shows a forecast card.",
      operations: [.add(plugin: "network", config: nil)],
      expectedStates: ["network": .active, "weather": .active]),
    TourStep(
      id: 6, title: "Recover a failed plugin", concept: "Failure handling",
      explanation: "flaky throws from apply, which leaves its fiber failed without affecting anyone else. A config update clears the failure and retries.",
      observe: "flaky becomes active and adds a card.",
      operations: [.updateConfig("flaky", .object(["fail": .bool(false)]))],
      expectedStates: ["flaky": .active]),
    TourStep(
      id: 7, title: "Withdraw an isolated service", concept: "Realms (isolation)",
      explanation: "The night group isolates the name theme into a private realm. night-card resolves theme to night-theme; theme-card outside the group resolves it to theme.",
      observe: "Only night-card goes pending; the Day theme card is untouched.",
      operations: [.setEnabled("night-theme", false)],
      expectedStates: ["night-card": .pending, "theme-card": .active]),
    TourStep(
      id: 8, title: "Disable a whole group", concept: "Groups",
      explanation: "A group entry runs its children under its own fiber. Disabling the group disposes the group and every child with it.",
      observe: "night, night-theme and night-card all leave the tree's active set.",
      operations: [.setEnabled("night-theme", true), .setEnabled("night", false)],
      expectedStates: ["night": .disabled, "night-theme": .inactive, "night-card": .inactive]),
    TourStep(
      id: 9, title: "Restart a stateful service", concept: "Lifecycle and state",
      explanation: "Tap + on the counter card a few times first. A restart creates a new counter instance, and the counter card reloads because the service it injects changed.",
      observe: "The counter starts again from 0.",
      operations: [.restart("counter")],
      expectedStates: ["counter": .active, "counter-card": .active]),
    TourStep(
      id: 10, title: "Reconcile back to the defaults", concept: "Loader reconciliation",
      explanation: "The loader diffs the new entry tree against the running one by id: removed entries are disposed, changed configs are updated, disabled flags are applied, and untouched entries keep running.",
      observe: "network is removed (weather goes back to pending), greeter and flaky return to their original configs, and the night group runs again.",
      operations: [.reset],
      expectedStates: ["weather": .pending, "flaky": .failed, "night-card": .active]),
  ]
}
