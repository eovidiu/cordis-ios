import Foundation
import Testing
@testable import Cordis

enum LoaderFooKey: ServiceKey {
  typealias Value = LoaderFoo
  static let name = "foo"
}

struct LabelConfig: Codable, Sendable, Equatable {
  var label: String?
}

@CordisActor @Service(LoaderFooKey.self)
final class LoaderFoo {
  typealias Config = LabelConfig
}

@CordisActor @Plugin
final class LoaderBar {
  typealias Config = LabelConfig
  @Inject(LoaderFooKey.self) var foo: LoaderFoo

  func apply(_ scope: EffectScope) async throws {
    // reading the declared service succeeds while the fiber runs
    _ = try foo
  }
}

@CordisActor @Plugin
final class LoaderPlain {
  func apply(_ scope: EffectScope) async throws {}
}

@Suite("LoaderTests")
@CordisActor
struct LoaderTests {
  private func catalog() -> PluginCatalog {
    var catalog = PluginCatalog()
    catalog.register(LoaderFoo.self, as: "foo")
    catalog.register(LoaderBar.self, as: "bar")
    catalog.register(LoaderPlain.self, as: "plain")
    return catalog
  }

  private func start(_ entries: [Entry]) async throws -> (Context, Loader, InMemoryEntryStore) {
    let root = Context()
    let store = InMemoryEntryStore(entries)
    let loader = Loader(ctx: root, catalog: catalog(), store: store)
    try await loader.start()
    return (root, loader, store)
  }

  @Test("start activates entries")
  func startActivatesEntries() async throws {
    let (_, loader, _) = try await start([
      Entry(id: "a", plugin: "foo"),
      Entry(id: "b", plugin: "bar"),
    ])
    #expect(loader.fiber(for: "a")?.state == .active)
    #expect(loader.fiber(for: "b")?.state == .active)
    #expect(loader.fiber(for: "b")?.name == "LoaderBar")
  }

  @Test("disable then enable")
  func disableThenEnable() async throws {
    let (_, loader, store) = try await start([
      Entry(id: "a", plugin: "foo"),
      Entry(id: "b", plugin: "bar"),
    ])
    let a = try #require(loader.fiber(for: "a"))
    let b = try #require(loader.fiber(for: "b"))

    try await loader.setDisabled(id: "a", true)
    #expect(a.state == .disposed)
    #expect(loader.fiber(for: "a") == nil)
    #expect(b.state == .pending)
    #expect(store.entries.first?.disabled == true)
    let json = String(decoding: try JSONEncoder().encode(store.entries), as: UTF8.self)
    #expect(json.contains("\"disabled\":true"))

    try await loader.setDisabled(id: "a", false)
    #expect(loader.fiber(for: "a")?.state == .active)
    #expect(b.state == .active)
    #expect(store.entries.first?.disabled == false)
  }

  @Test("update writes config")
  func updateWritesConfig() async throws {
    let (_, loader, store) = try await start([
      Entry(id: "a", plugin: "foo"),
      Entry(id: "b", plugin: "bar", config: .object(["label": .string("old")])),
    ])
    let b = try #require(loader.fiber(for: "b"))
    #expect((b.config as? LabelConfig)?.label == "old")

    try await loader.update(id: "b", config: .object(["label": .string("new")]))
    #expect(loader.fiber(for: "b") === b)
    #expect((b.config as? LabelConfig)?.label == "new")
    #expect(b.state == .active)
    #expect(store.entries[1].config == .object(["label": .string("new")]))

    // a config changed through the fiber is written back to its entry
    try await b.update(LabelConfig(label: "direct"))
    #expect(store.entries[1].config == .object(["label": .string("direct")]))
    #expect(loader.entry("b")?.config == .object(["label": .string("direct")]))
  }

  @Test("plugin rename recreates the fiber")
  func pluginRenameRecreatesFiber() async throws {
    let (_, loader, _) = try await start([Entry(id: "x", plugin: "plain")])
    let old = try #require(loader.fiber(for: "x"))
    var entries = loader.entries
    entries[0].plugin = "foo"
    try await loader.reconcile(entries)
    let new = try #require(loader.fiber(for: "x"))
    #expect(old.state == .disposed)
    #expect(new !== old)
    #expect(new.state == .active)
    #expect(new.name == "foo")
  }

  @Test("group reconciles children by id")
  func groupReconcilesChildren() async throws {
    let (root, loader, store) = try await start([
      Entry(id: "g", plugin: "group", children: [
        Entry(id: "c1", plugin: "foo"),
        Entry(id: "c2", plugin: "bar"),
      ]),
    ])
    let group = try #require(loader.fiber(for: "g"))
    let c1 = try #require(loader.fiber(for: "c1"))
    let c2 = try #require(loader.fiber(for: "c2"))
    #expect(group.state == .active)
    #expect(c1.state == .active)
    #expect(c2.state == .active)
    #expect(c2.parent.fiber === group)

    try await loader.add(Entry(id: "c3", plugin: "plain"), parent: "g")
    #expect(loader.fiber(for: "c1") === c1)
    #expect(loader.fiber(for: "c3")?.state == .active)
    #expect(store.entries[0].children?.map(\.id) == ["c1", "c2", "c3"])

    try await loader.remove(id: "c1")
    #expect(c1.state == .disposed)
    #expect(c2.state == .pending)
    #expect(loader.fiber(for: "c2") === c2)

    try await loader.setDisabled(id: "g", true)
    #expect(group.state == .disposed)
    #expect(c2.state == .disposed)
    #expect(root.registry.get(LoaderBar.self) == nil)
  }

  @Test("unknown plugin is logged and skipped")
  func unknownPluginIsLogged() async throws {
    let (root, loader, store) = try await start([
      Entry(id: "u", plugin: "missing"),
      Entry(id: "a", plugin: "foo"),
    ])
    #expect(loader.fiber(for: "u") == nil)
    #expect(loader.fiber(for: "a")?.state == .active)
    #expect(root.logger.buffer.contains { $0.level == .error && $0.text == "plugin \"missing\" is not in the catalog" })
    #expect(store.entries.map(\.id) == ["u", "a"])
  }

  @Test("shared isolation realm")
  func sharedIsolationRealm() async throws {
    let (root, loader, _) = try await start([
      Entry(id: "s1", plugin: "foo", isolate: ["foo": .shared("x")]),
      Entry(id: "s2", plugin: "bar", isolate: ["foo": .shared("x")]),
      Entry(id: "s3", plugin: "bar"),
    ])
    #expect(loader.fiber(for: "s2")?.state == .active)
    #expect(loader.fiber(for: "s3")?.state == .pending)
    #expect(root.get(LoaderFooKey.self, strict: false) == nil)
  }
}
