import ShowcaseKit
import SwiftUI

enum AppTab: String, CaseIterable {
  case tour, dashboard, plugins, services, timeline
}

struct RootView: View {
  @Environment(ShowcaseStore.self) private var store
  @State private var tab = AppTab(rawValue: UserDefaults.standard.string(forKey: "tab") ?? "") ?? .tour

  var body: some View {
    @Bindable var store = store
    TabView(selection: $tab) {
      TourView(tab: $tab)
        .tabItem { Label("Tour", systemImage: "map") }
        .tag(AppTab.tour)
      DashboardView()
        .tabItem { Label("Dashboard", systemImage: "square.grid.2x2") }
        .tag(AppTab.dashboard)
      PluginsView()
        .tabItem { Label("Plugins", systemImage: "puzzlepiece.extension") }
        .tag(AppTab.plugins)
      ServicesView()
        .tabItem { Label("Services", systemImage: "point.3.connected.trianglepath.dotted") }
        .tag(AppTab.services)
      TimelineView()
        .tabItem { Label("Timeline", systemImage: "list.bullet.rectangle") }
        .tag(AppTab.timeline)
    }
    .alert(item: $store.problem) { problem in
      Alert(title: Text(problem.title), message: Text(problem.message))
    }
  }
}

/// Toolbar spinner shown while an operation runs.
struct BusyIndicator: View {
  @Environment(ShowcaseStore.self) private var store

  var body: some View {
    if store.isBusy {
      ProgressView()
    }
  }
}
