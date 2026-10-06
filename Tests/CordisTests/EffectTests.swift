import Testing
@testable import Cordis

@Suite("EffectTests")
@CordisActor
struct EffectTests {
  @Test("dispose by plugin")
  func disposeByPlugin() async throws {
    let root = Context()
    let disposed = Recorder<Void>()
    let fiber = try await root.plugin(plugin { ctx, _, _ in
      try ctx.effect("test", sync: { { disposed.record(()) } })
    }).await()
    #expect(fiber.getEffects() == [EffectMeta(label: "test")])
    #expect(disposed.count == 0)
    try await fiber.dispose()
    #expect(disposed.count == 1)
    try await fiber.dispose()
    #expect(disposed.count == 1)
  }

  @Test("dispose manually")
  func disposeManually() async throws {
    let root = Context()
    let disposed = Recorder<Void>()
    let handle = try root.effect(sync: { { disposed.record(()) } })
    #expect(root.fiber.getEffects() == [EffectMeta(label: "anonymous")])
    #expect(disposed.count == 0)
    try await handle.dispose()
    #expect(disposed.count == 1)
    try await handle.dispose()
    #expect(disposed.count == 1)
  }

  @Test("yield dispose")
  func yieldDispose() async throws {
    let root = Context()
    let seq = Recorder<Int>()
    let handle = try root.effect(scoped: { scope in
      try scope.collect { seq.record(1) }
      try scope.collect(root.on(CustomEvent.self) { _ in })
      try scope.collect { seq.record(2) }
      try scope.collect(root.effect(scoped: { scope in
        try scope.collect(root.on(CustomEvent.self) { _ in })
        try scope.collect { seq.record(3) }
      }))
    })
    try root.on(CustomEvent.self) { _ in }
    #expect(root.fiber.getEffects() == [
      EffectMeta(label: "anonymous", children: [
        // only root level anonymous effects are included
        EffectMeta(label: "ctx.on(\"custom-event\")"),
        EffectMeta(label: "anonymous", children: [
          EffectMeta(label: "ctx.on(\"custom-event\")"),
        ]),
      ]),
      EffectMeta(label: "ctx.on(\"custom-event\")"),
    ])
    #expect(seq.calls == [])
    try await handle.dispose()
    #expect(seq.calls == [3, 2, 1])
    try await handle.dispose()
    #expect(seq.calls == [3, 2, 1])
  }

  @Test("async return 1")
  func asyncReturn1() async throws {
    let root = Context()
    let seq = Recorder<Int>()
    let gate = Gate()
    let handle = try root.effect { scope in
      await gate.wait()
      seq.record(1)
      try scope.collect { seq.record(2) }
    }
    #expect(seq.calls == [])
    gate.open()
    try await handle.ready()
    #expect(seq.calls == [1])
    try await handle.dispose()
    #expect(seq.calls == [1, 2])
  }

  @Test("async return 2")
  func asyncReturn2() async throws {
    let root = Context()
    let seq = Recorder<Int>()
    let gate = Gate()
    let handle = try root.effect { scope in
      await gate.wait()
      seq.record(1)
      try scope.collect { seq.record(2) }
    }
    let disposing = Task { try await handle.dispose() }
    await settle()
    #expect(seq.calls == [])
    gate.open()
    try await disposing.value
    #expect(seq.calls == [1, 2])
  }

  private func threeStepEffect(_ root: Context, _ seq: Recorder<Int>, _ gates: GateList) throws -> EffectHandle {
    try root.effect { scope in
      await gates.wait()
      seq.record(1)
      try scope.collect { seq.record(2) }
      await gates.wait()
      seq.record(3)
      try scope.collect { seq.record(4) }
      await gates.wait()
      seq.record(5)
      try scope.collect { seq.record(6) }
    }
  }

  @Test("async yield 1")
  func asyncYield1() async throws {
    let root = Context()
    let seq = Recorder<Int>()
    let gates = GateList()
    let handle = try threeStepEffect(root, seq, gates)
    #expect(seq.calls == [])
    for index in 0..<3 { gates.gate(index).open() }
    await settle()
    #expect(seq.calls == [1, 3, 5])
    try await handle.dispose()
    #expect(seq.calls == [1, 3, 5, 6, 4, 2])
  }

  @Test("async yield 2 (aborted)")
  func asyncYield2Aborted() async throws {
    let root = Context()
    let seq = Recorder<Int>()
    let gates = GateList()
    let handle = try threeStepEffect(root, seq, gates)
    await settle()
    let disposing = Task { try await handle.dispose() }
    await settle()
    #expect(seq.calls == [])
    for index in 0..<3 { gates.gate(index).open() }
    try await disposing.value
    #expect(seq.calls == [1, 2])
    #expect(errorCount(root) == 0)
  }

  @Test("async yield 3 (aborted)")
  func asyncYield3Aborted() async throws {
    let root = Context()
    let seq = Recorder<Int>()
    let gates = GateList()
    let handle = try threeStepEffect(root, seq, gates)
    #expect(seq.calls == [])
    gates.gate(0).open()
    await settle()
    #expect(seq.calls == [1])
    let disposing = Task { try await handle.dispose() }
    await settle()
    #expect(seq.calls == [1])
    gates.gate(1).open()
    gates.gate(2).open()
    try await disposing.value
    #expect(seq.calls == [1, 3, 4, 2])
  }

  @Test("async yield 4 (await dispose)")
  func asyncYield4AwaitDispose() async throws {
    let root = Context()
    let seq = Recorder<Int>()
    let gates = GateList()
    let handle = try threeStepEffect(root, seq, gates)
    #expect(seq.calls == [])
    for index in 0..<3 { gates.gate(index).open() }
    try await handle.ready()
    #expect(seq.calls == [1, 3, 5])
    try await handle.dispose()
    #expect(seq.calls == [1, 3, 5, 6, 4, 2])
  }

  @Test("return with error")
  func returnWithError() async throws {
    let root = Context()
    let seq = Recorder<Int>()
    #expect(throws: TestError("test")) {
      try root.effect(sync: {
        if seq.count == 0 { throw TestError("test") }
        return { seq.record(1) }
      })
    }
    await settle()
    #expect(seq.calls == [])
  }

  @Test("yield with error")
  func yieldWithError() async throws {
    let root = Context()
    let seq = Recorder<Int>()
    #expect(throws: TestError("test")) {
      try root.effect(scoped: { scope in
        try scope.collect { seq.record(1) }
        throw TestError("test")
      })
    }
    await settle()
    #expect(seq.calls == [1])
  }

  @Test("async return with error")
  func asyncReturnWithError() async throws {
    let root = Context()
    let seq = Recorder<Int>()
    let handle = try root.effect { scope in
      await Task.yield()
      if seq.count == 0 { throw TestError("test") }
      try scope.collect { seq.record(1) }
    }
    #expect(seq.calls == [])
    do {
      try await handle.ready()
      Issue.record("ready() did not throw")
    } catch {
      #expect(error as? TestError == TestError("test"))
    }
    #expect(seq.calls == [])
  }

  @Test("async yield with error")
  func asyncYieldWithError() async throws {
    let root = Context()
    let seq = Recorder<Int>()
    let handle = try root.effect { scope in
      await Task.yield()
      try scope.collect { seq.record(1) }
      throw TestError("test")
    }
    #expect(seq.calls == [])
    do {
      try await handle.ready()
      Issue.record("ready() did not throw")
    } catch {
      #expect(error as? TestError == TestError("test"))
    }
    #expect(seq.calls == [1])
  }
}
