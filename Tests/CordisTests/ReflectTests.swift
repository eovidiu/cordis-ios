import Testing
@testable import Cordis

@Suite("ReflectTests")
@CordisActor
struct ReflectTests {
  @Test("access check")
  func accessCheck() async throws {
    let root = Context()

    try await root.plugin(plugin { ctx, _, _ in
      expectError("cannot get property \"bar\" without inject") { _ = try ctx[Bar.self] }
      expectError("cannot set property \"bar\" without provide") { try ctx.set(Bar.self, 0) }
    }).await()

    try await root.plugin(plugin { ctx, _, _ in
      expectError("cannot set property \"foo\" without provide") { try ctx.set(Foo.self, Payload(bar: 0)) }
      #expect(throws: Never.self) { try ctx.provide(Foo.self) }
      expectError("service \"foo\" has been registered at <root>") { try ctx.provide(Foo.self) }
      #expect(throws: Never.self) { try ctx.set(Foo.self, Payload(bar: 0)) }
    }).await()
  }

  @Test("service inject leak")
  func serviceInjectLeak() async throws {
    let root = Context()
    try root.provide(Foo.self)
    try root.set(Foo.self, Payload(bar: 1))
    let fiber = try await root.inject([Foo.self]) { _, _ in }.await()
    #expect(try fiber.ctx[Foo.self] == Payload(bar: 1))
    try await fiber.dispose()
    expectError("cannot get required service \"foo\" in inactive context") { _ = try fiber.ctx[Foo.self] }
  }
}
