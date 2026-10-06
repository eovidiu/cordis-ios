# Architecture (C4 model)

This page describes cordis-ios with the [C4 model](https://c4model.com): system context, containers, components and code. Each level zooms into one box of the level above. Dynamic and deployment views follow the static levels. The diagrams are Mermaid source in [`docs/pages/architecture.md`](https://github.com/eovidiu/cordis-ios/blob/main/docs/pages/architecture.md), so they change with the code in the same commit.

| Level | Diagram | Question it answers |
| --- | --- | --- |
| 1 | [System context](#level-1-system-context) | Who uses cordis-ios, and what does it depend on? |
| 2 | [Containers](#level-2-containers) | Which modules, apps and stores make up the repository? |
| 3 | [Components: Cordis library](#level-3-components-cordis-library) | What are the parts of the plugin runtime? |
| 3 | [Components: CordisShowcase](#level-3-components-cordisshowcase) | How does the demo app sit on top of the runtime? |
| 4 | [Code](#level-4-code) | Which types implement the runtime, and how does a fiber change state? |
| + | [Dynamic views](#dynamic-views) | What happens, step by step, when a service goes away or a plugin loads? |
| + | [Deployment](#deployment) | Where does each part run? |

## Level 1: System context

cordis-ios is a Swift package. App developers write plugins against it, and the runtime loads and unloads those plugins as the services they depend on appear and disappear. The TypeScript [cordis](https://github.com/cordiverse/cordis) project is the behavioural specification: its tests were ported, and every difference from it is listed in the [README](https://github.com/eovidiu/cordis-ios#differences-from-cordis).

```mermaid
C4Context
  title System context: cordis-ios

  Person(dev, "App developer", "Builds iOS and macOS apps out of plugins")
  Person(user, "App user", "Uses an app built on cordis-ios, such as CordisShowcase")

  System(cordis, "cordis-ios", "Swift package: plugin runtime, persisted plugin loader, Swift macros, demo apps")

  System_Ext(spec, "cordis (TypeScript)", "cordiverse/cordis at f8ea3cd. Behavioural spec and source of the ported tests")
  System_Ext(syntax, "swift-syntax", "Compiler plugin APIs that the @Plugin, @Service and @Inject macros use")
  System_Ext(apple, "Apple platforms", "iOS 17+, macOS 14+, Swift concurrency, OSLog, SwiftUI")
  System_Ext(github, "GitHub", "Source hosting and the Pages site for these docs")

  Rel(dev, cordis, "Writes plugins and services with", "Swift")
  Rel(user, cordis, "Uses apps built on")
  Rel(cordis, spec, "Ports behaviour and tests from")
  Rel(cordis, syntax, "Expands macros with", "SwiftPM")
  Rel(cordis, apple, "Runs on")
  Rel(dev, github, "Reads docs on")

  UpdateLayoutConfig($c4ShapeInRow="3", $c4BoundaryInRow="1")
```

## Level 2: Containers

The repository holds one library, one compiler plugin, two demos and their test suites. Both demos persist their plugin tree as an `entries.json` file that the `Loader` reads and writes.

```mermaid
C4Container
  title Containers: cordis-ios repository

  Person(dev, "App developer")
  Person(user, "App user")

  System_Boundary(repo, "cordis-ios") {
    Container(lib, "Cordis", "Swift library, Swift 6", "Context, fibers, effects, services, events, logger, loader")
    Container(macros, "CordisMacros", "Swift compiler plugin", "Expands @Plugin, @Service and @Inject into Plugin conformances and inject lists")
    Container(cli, "cordis-demo", "Swift executable plus CordisDemoKit", "Command-line demo that toggles a service and prints fiber states")
    Container(kit, "ShowcaseKit", "Swift package", "Showcase engine, plugins, tour and the main-actor store")
    Container(app, "CordisShowcase", "SwiftUI iOS app", "Tour, dashboard, plugin tree, services and event timeline")
    ContainerDb(entries, "entries.json", "JSON file", "Persisted plugin entry tree: ids, plugin names, configs, disabled flags, isolation, groups")
    Container(docs, "Docs site", "Static HTML and Markdown on GitHub Pages", "This documentation")
  }

  Rel(dev, lib, "Depends on", "SwiftPM")
  Rel(user, app, "Taps through")
  Rel(lib, macros, "Declares macros implemented by")
  Rel(cli, lib, "Uses")
  Rel(kit, lib, "Uses")
  Rel(app, kit, "Renders snapshots from, sends operations to")
  Rel(kit, entries, "Loads and saves through Loader", "FileEntryStore")
  Rel(dev, docs, "Reads")

  UpdateLayoutConfig($c4ShapeInRow="3", $c4BoundaryInRow="1")
```

| Container | Path | Tested by |
| --- | --- | --- |
| Cordis | `Sources/Cordis` | `swift test` (`Tests/CordisTests`, ported from cordis) |
| CordisMacros | `Sources/CordisMacros` | `Tests/CordisMacrosTests` (expansion tests) |
| cordis-demo | `Sources/CordisDemo`, `Sources/CordisDemoKit` | `Tests/CordisTests/DemoTests.swift` |
| ShowcaseKit | `Examples/CordisShowcase/ShowcaseKit` | `swift test --package-path Examples/CordisShowcase/ShowcaseKit` |
| CordisShowcase | `Examples/CordisShowcase/App` | `Examples/CordisShowcase/run.sh uitest` (XCUITest) |
| Docs site | `docs/` | `docs/check.sh` |

## Level 3: Components, Cordis library

Every runtime object lives on one global actor, `CordisActor`, which takes the place of JavaScript's single thread. A `Context` is the handle that plugins receive. Each context also exposes the root services shared by its tree: registry, reflect, events and logger.

```mermaid
C4Component
  title Components: Cordis library

  Container(kit, "ShowcaseKit / your app", "Swift", "Registers plugins and drives the loader")

  Container_Boundary(lib, "Cordis") {
    Component(context, "Context", "@CordisActor class", "Plugin handle: plugin(), provide(), ctx[Key], on/emit, effect(), isolate()")
    Component(fiber, "Fiber", "@CordisActor class", "One running plugin instance: state machine, inject list, effects, config")
    Component(effects, "Effects", "EffectScope, EffectHandle", "Collect disposers; unloading runs them newest first")
    Component(registry, "RegistryService", "Runtime per plugin identity", "Creates fibers, hands out uids, deletes plugins")
    Component(reflect, "ReflectService", "Impl per realm", "Provides services per realm and notifies the fibers that inject them")
    Component(events, "EventsService", "Hooks", "emit, parallel, serial, bail, waterfall; internal/status, internal/service, internal/plugin, internal/update")
    Component(logger, "LoggerService", "Buffer and exporters", "Error boundary for plugin failures; OSLog, print and closure exporters")
    Component(loader, "Loader", "EntryReconciler, GroupPlugin", "Reconciles the persisted entry tree with running fibers by entry id")
    Component(catalog, "PluginCatalog", "Name to AnyPlugin", "Resolves an entry's plugin name")
    Component(store, "EntryStore", "FileEntryStore, InMemoryEntryStore", "Loads and saves the entry tree")
    Component(macrosdecl, "Macro declarations", "@Plugin, @Service, @Inject", "Generate ctx, config, init, inject and the conformance")
  }

  Rel(kit, loader, "start, add, update, setDisabled, remove, reconcile")
  Rel(loader, catalog, "resolves plugin names")
  Rel(loader, store, "load and save")
  Rel(loader, context, "plugs entries into isolated child contexts")
  Rel(context, registry, "plugin()")
  Rel(registry, fiber, "creates")
  Rel(fiber, effects, "owns")
  Rel(context, reflect, "provide() and ctx[Key]")
  Rel(reflect, fiber, "checkImpl and refresh on change")
  Rel(fiber, events, "emits internal/status")
  Rel(fiber, logger, "logs apply() errors")

  UpdateLayoutConfig($c4ShapeInRow="3", $c4BoundaryInRow="1")
```

The rules that tie these components together:

- **Services gate plugins.** A fiber's *epoch* is built from the uids of the fibers that provide each service it injects. A missing service makes the epoch inactive, so the fiber unloads to `pending`. When every service is present, the fiber loads. When a provider is replaced, the epoch changes and the fiber reloads.
- **Effects make unloading total.** Everything a plugin installs is an effect: service provisions, listeners, child plugins, logger exporters, and the showcase's dashboard cards. Unloading runs the collected disposers newest first. No plugin needs its own teardown code.
- **Realms isolate names.** `ctx.isolate("theme")` gives a context its own realm for `theme`. A provider and a consumer see each other only when their contexts resolve the name to the same realm.

## Level 3: Components, CordisShowcase

The showcase keeps cordis on `CordisActor` and SwiftUI on the main actor. Cordis-side state crosses to the UI only as immutable `ShowcaseSnapshot` values.

```mermaid
C4Component
  title Components: CordisShowcase app and ShowcaseKit

  Person(user, "App user")

  Container_Boundary(appb, "CordisShowcase app (SwiftUI)") {
    Component(tour, "TourView", "SwiftUI", "Ten guided steps with live entry states")
    Component(dash, "DashboardView", "SwiftUI", "Grid of plugin-contributed cards")
    Component(plugins, "PluginsView", "SwiftUI", "Entry tree, toggles, config editor, effects list")
    Component(services, "ServicesView, TimelineView", "SwiftUI", "Services per realm; internal events and logs")
  }

  Container_Boundary(kitb, "ShowcaseKit") {
    Component(storec, "ShowcaseStore", "@MainActor @Observable", "Holds the latest snapshot; runs operations")
    Component(engine, "ShowcaseEngine", "@CordisActor", "Root context, Loader, listeners, timeline, snapshots")
    Component(dashsvc, "DashboardService", "Host service 'dashboard'", "Cards installed as effects of the contributing plugin")
    Component(plug, "Showcase plugins", "@Service and @Plugin classes", "clock, counter, network, theme services; card, greeter, weather, flaky, audit plugins")
    Component(tourmodel, "TourStep, ShowcaseCatalog", "Static data", "Tour operations, expected states, catalog metadata, default entries")
  }

  ContainerDb(entries, "entries.json", "Application Support")
  Container(lib, "Cordis", "Swift library")

  Rel(user, tour, "Runs steps")
  Rel(user, plugins, "Toggles and edits entries")
  Rel(tour, storec, "run(operation)")
  Rel(plugins, storec, "run(operation), updateConfig")
  Rel(dash, storec, "reads cards, triggers card actions")
  BiRel(storec, engine, "operations, snapshots")
  Rel(engine, lib, "Loader, Context, events")
  Rel(plug, dashsvc, "contribute(from: ctx, card)")
  Rel(engine, dashsvc, "provides at root")
  Rel(engine, entries, "via FileEntryStore")
  Rel(engine, tourmodel, "uses")

  UpdateLayoutConfig($c4ShapeInRow="3", $c4BoundaryInRow="1")
```

## Level 4: Code

### Runtime types

```mermaid
classDiagram
  direction LR
  class Context {
    +parent: Context?
    +root: Context
    +fiber: Fiber
    +registry: RegistryService
    +reflect: ReflectService
    +events: EventsService
    +logger: Logger
    +plugin(type, config) Fiber
    +provide(key, value, check) EffectHandle
    +subscript(key) Value
    +get(key, strict) Value?
    +on(event, listener) EffectHandle
    +emit(event, args)
    +effect(label, body) EffectHandle
    +isolate(name, realm) Context
  }
  class Fiber {
    +uid: Int?
    +state: FiberState
    +config: Sendable?
    +inject: [String: Sendable?]
    +runtime: Runtime?
    +error: Error?
    +inertia: Task?
    +ctx: Context
    +await() Fiber
    +restart()
    +update(config, noSave)
    +dispose()
    +getEffects() [EffectMeta]
  }
  class FiberState {
    <<enumeration>>
    pending
    loading
    active
    failed
    unloading
    disposed
  }
  class Plugin {
    <<protocol>>
    +Config: Decodable
    +name: String
    +inject: [ServiceKey.Type]
    +validate(config)
    +init(ctx, config)
    +apply(scope)
  }
  class ServicePlugin {
    <<protocol>>
    +Key: ServiceKey
    +setup(scope)
    +check() Bool
  }
  class Runtime {
    +name: String?
    +identity: PluginIdentity
    +fiberList: [Fiber]
  }
  class RegistryService {
    +runtimes: [Runtime]
    +get(plugin) Runtime?
    +delete(plugin) Runtime?
  }
  class ReflectService {
    +props: Set~String~
    +store: [Realm: Impl]
  }
  class Impl {
    +name: String
    +value: Sendable?
    +fiber: Fiber
    +ctx: Context
  }
  class EffectHandle {
    +label: String
    +meta: EffectMeta
    +ready()
    +dispose()
  }
  class EffectScope {
    +collect(disposer)
    +collect(handle)
  }
  class Loader {
    +ctx: Context
    +catalog: PluginCatalog
    +entries: [Entry]
    +start()
    +add(entry, parent)
    +update(id, config)
    +setDisabled(id, disabled)
    +remove(id)
    +reconcile(entries)
    +fiber(for id) Fiber?
  }
  class Entry {
    +id: String
    +plugin: String
    +config: JSONValue?
    +disabled: Bool
    +isolate: [String: IsolateSpec]?
    +children: [Entry]?
  }

  ServicePlugin --|> Plugin
  Context "1" --> "1" Fiber : fiber
  Fiber --> FiberState
  Fiber --> Runtime : runtime
  Fiber "1" o-- "*" EffectHandle : disposables
  RegistryService "1" o-- "*" Runtime
  Runtime "1" o-- "*" Fiber : fibers
  ReflectService "1" o-- "*" Impl : per realm
  Impl --> Fiber : provider
  EffectHandle ..> EffectScope : body receives
  Loader --> Context
  Loader "1" o-- "*" Entry
  Plugin ..> Context : init(ctx)
```

### Fiber state machine

A fiber moves between states as its injected services come and go. Every transition is emitted as `internal/status`. The Timeline tab in the showcase shows these events as they happen.

```mermaid
stateDiagram-v2
  [*] --> pending: ctx.plugin()
  pending --> loading: every injected service available
  loading --> active: apply() returned
  loading --> unloading: apply() threw, or a service went away meanwhile
  active --> unloading: a service went away, restart(), update() or dispose()
  unloading --> pending: services missing
  unloading --> loading: services available again (reload)
  unloading --> failed: apply() threw
  failed --> loading: update(config) clears the error
  pending --> disposed: dispose()
  unloading --> disposed: dispose() finished
  failed --> disposed: dispose()
  disposed --> [*]
```

### Macro expansion

`@Plugin` and `@Service` remove the boilerplate that every plugin would otherwise repeat:

```swift
@CordisActor @Plugin
final class ClockCardPlugin {
  @Inject(DashboardKey.self) var dashboard: DashboardService
  @Inject(ClockKey.self) var clock: ClockService
  func apply(_ scope: EffectScope) async throws { … }
}
// @Plugin adds these members:
public let ctx: Context
public let config: NoConfig          // the class's `typealias Config`, if it declares one
public init(ctx: Context, config: NoConfig) { self.ctx = ctx; self.config = config }
public nonisolated static var inject: [any ServiceKey.Type] { [DashboardKey.self, ClockKey.self] }
// and this conformance:
extension ClockCardPlugin: Cordis.Plugin {}
// Each @Inject property becomes a throwing getter:
var dashboard: DashboardService { get throws { try ctx[DashboardKey.self] } }
```

## Dynamic views

### Withdrawing a service

This is tour step 1, *disable clock*. The UI never removes the clock card itself. The card goes away because it is an effect of `clock-card`, and `clock-card` unloads when its injected `clock` service is withdrawn.

```mermaid
sequenceDiagram
  autonumber
  actor User
  participant UI as TourView / PluginsView
  participant Store as ShowcaseStore (MainActor)
  participant Engine as ShowcaseEngine (CordisActor)
  participant Loader
  participant Clock as clock fiber
  participant Reflect as ReflectService
  participant Card as clock-card fiber
  participant Dash as DashboardService

  User->>UI: Run step 1
  UI->>Store: run(.setEnabled("clock", false))
  Store->>Engine: await run(operation)
  Engine->>Loader: setDisabled(id: "clock", true)
  Loader->>Loader: save entries.json
  Loader->>Clock: dispose()
  Clock->>Clock: unload: run disposers, newest first
  Clock->>Reflect: disposer of ctx.provide("clock")
  Reflect->>Card: checkImpl("clock"), refresh()
  Card->>Card: epoch inactive: active to unloading
  Card->>Dash: disposer of dashboard card "Clock"
  Dash-->>Engine: onChange
  Card->>Card: unloading to pending (internal/status)
  Clock->>Clock: unloading to disposed
  Engine->>Engine: settle(): wait for in-flight transitions
  Engine-->>Store: ShowcaseSnapshot (revision n)
  Store-->>UI: Observation update: card gone, badges pending/disabled
```

### Loading a plugin whose service arrives late

This is tour step 5. `weather` has been `pending` since launch because nothing provides `network`. Adding a network entry starts the load. The plugin's `apply` then waits on a simulated request, so the fiber stays in `loading` long enough to watch.

```mermaid
sequenceDiagram
  autonumber
  participant Engine as ShowcaseEngine
  participant Loader
  participant Registry as RegistryService
  participant Net as network fiber
  participant Reflect as ReflectService
  participant Weather as weather fiber
  participant Dash as DashboardService

  Engine->>Loader: add(Entry(id: "network", plugin: "network"))
  Loader->>Registry: entryCtx.plugin(NetworkService, rawConfig)
  Registry->>Net: Fiber(uid), start(): resolve and validate config
  Net->>Net: pending to loading, apply(): ctx.provide("network")
  Net->>Net: loading to active
  Net->>Reflect: updateState notifies "network"
  Reflect->>Weather: checkImpl("network"), refresh(): epoch complete
  Weather->>Weather: pending to loading
  Weather->>Net: forecast(for: city), about 1.2 s
  Weather->>Dash: contribute(from: ctx, card)
  Weather->>Weather: loading to active
```

## Deployment

```mermaid
C4Deployment
  title Deployment: development and distribution

  Deployment_Node(mac, "Developer Mac", "macOS, Xcode 26, XcodeGen") {
    Container(spm, "SwiftPM build and tests", "swift test", "Cordis and ShowcaseKit tests on macOS")
    Deployment_Node(sim, "iOS Simulator", "iPhone 17 Pro, iOS 26") {
      Container(appsim, "CordisShowcase", "Debug build", "run.sh sim, run.sh uitest")
    }
  }
  Deployment_Node(phone, "iPhone XR", "iOS 18, USB or Wi-Fi pairing") {
    Container(appdev, "CordisShowcase", "Development-signed build", "run.sh device")
    ContainerDb(file, "entries.json", "Application Support")
  }
  Deployment_Node(gh, "GitHub", "github.com/eovidiu/cordis-ios") {
    Container(pages, "GitHub Pages", "main:/docs", "This site")
  }

  Rel(spm, appsim, "xcodebuild, simctl install")
  Rel(spm, appdev, "xcodebuild, devicectl install")
  Rel(appdev, file, "reads and writes")
```
