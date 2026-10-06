# cordis-ios

A native Swift (iOS 17+/macOS 14+) port of the [cordis](https://github.com/cordiverse/cordis) meta-framework core and loader (commit `f8ea3cd`, `cordis@4.0.0-rc.10`; paper [arXiv 2608.25512](https://arxiv.org/abs/2608.25512)). Apps are built from plugins that can be switched on and off at runtime: removing a plugin reverts every effect it installed, and a plugin runs only while every service it declares is provided.

## Usage

```swift
import Cordis
import Foundation

enum ClockKey: ServiceKey {
  typealias Value = ClockService
  static let name = "clock"
}

@CordisActor @Service(ClockKey.self)
final class ClockService {
  func now() -> Date { Date() }
}

@CordisActor @Plugin
final class Greeter {
  @Inject(ClockKey.self) var clock: ClockService   // generates `inject = [ClockKey.self]`

  func apply(_ scope: EffectScope) async throws {
    print("hello at \(try clock.now())")
    try scope.collect { print("bye") }              // runs when the plugin is unloaded
  }
}

@CordisActor func run() async throws {
  let root = Context()
  let greeter = try root.plugin(Greeter.self)       // pending: no clock yet
  let clock = try await root.plugin(ClockService.self).await()
  try await greeter.await()                          // active
  try await clock.dispose()                          // greeter unloads ("bye"), back to pending
}
```

Persisted entries are run by `Loader`:

```swift
var catalog = PluginCatalog()
catalog.register(ClockService.self, as: "clock")
catalog.register(Greeter.self, as: "greeter")
let loader = Loader(ctx: root, catalog: catalog, store: FileEntryStore(url: entriesURL))
try await loader.start()
try await loader.setDisabled(id: "clock", true)
```

`swift run cordis-demo` shows the loader toggling a service and its dependent plugin.

## Showcase app

[`Examples/CordisShowcase`](Examples/CordisShowcase) is a SwiftUI app for iPhone and iPad (iOS 17+) built from plugins run by a `Loader`. Every card on its dashboard is a dashboard-service effect of the plugin that added it. A guided tour withdraws and restores services, updates and rejects configs, recovers a failed plugin, adds a missing service, isolates a service in a realm, and reconciles the entry tree. Other tabs list the entry tree with live fiber states, the services in each realm, and the `internal/*` event timeline.

```sh
brew install xcodegen                                  # the Xcode project is generated
Examples/CordisShowcase/run.sh sim                     # build and launch on a simulator
TEAM_ID=<team> DEVICE="My iPhone" Examples/CordisShowcase/run.sh device
Examples/CordisShowcase/run.sh test                    # engine tests (swift test, macOS)
Examples/CordisShowcase/run.sh uitest                  # XCUITest suite on a simulator
```

The engine, plugins and observable store live in the `ShowcaseKit` package next to the app. The `App` target contains only SwiftUI views.

## Differences from cordis

- No `Proxy`: services are read through typed keys (`ctx[Key.self]`), which implement the paper's Algorithm 6 resolution walk. Shadows, callable services, mixins and accessors are not ported.
- One global actor, `CordisActor`, replaces JavaScript's single thread. Contexts, fibers, services, listeners and plugins are isolated to it.
- `Realm` values replace `Symbol` isolation labels.
- Effects are `ctx.effect(sync:)` (returns a disposer), `ctx.effect(scoped:)` (sync generator) or `ctx.effect { scope in … }` (async generator; each `scope.collect` is a `yield`). A trailing closure without `await` picks the sync `scoped:` form.
- `ctx.on` listeners return `Void` and never bail; `ctx.onBail` listeners return `Result?`, where non-nil bails. `emit` is synchronous; async listeners under `emit` run as tasks whose errors are logged.
- Configs are `Decodable & Sendable` with an optional `validate`; failures throw `ValidationError` in cordis's message format.
- A fiber unloads its effects one after another (newest first) rather than concurrently.
- The loader has no hot reload, and an `isolate` change rebuilds the entry's fiber instead of reassigning realms in place.
