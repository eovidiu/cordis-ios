import ShowcaseKit
import SwiftUI

@main
struct CordisShowcaseApp: App {
  @State private var store: ShowcaseStore?

  var body: some Scene {
    WindowGroup {
      Group {
        if let store {
          RootView()
            .environment(store)
        } else {
          ProgressView("Starting cordis…")
        }
      }
      .task {
        guard store == nil else { return }
        store = await Self.makeStore()
      }
    }
  }

  /// Launch arguments (read through `UserDefaults`' argument domain):
  /// `-resetEntries YES` starts from the default entries, `-tourSteps N`
  /// runs the first N tour steps after launch.
  private static func makeStore() async -> ShowcaseStore {
    let defaults = UserDefaults.standard
    if defaults.bool(forKey: "resetEntries") {
      try? FileManager.default.removeItem(at: ShowcaseStore.entriesURL)
    }
    let store = await ShowcaseStore.live()
    await store.start()
    let steps = defaults.integer(forKey: "tourSteps")
    for step in TourStep.all.prefix(steps) {
      for operation in step.operations {
        await store.run(operation)
      }
    }
    return store
  }
}
