import Testing
@testable import Cordis

@Suite("EventsTests")
@CordisActor
struct EventsTests {
  @Test("removes empty event buckets after disposal")
  func removesEmptyBuckets() async throws {
    let root = Context()
    let first = try root.on(CustomEvent.self) { _ in }
    let second = try root.on(CustomEvent.self) { _ in }
    try await first.dispose()
    #expect(root.events.hooks[CustomEvent.name] != nil)
    try await second.dispose()
    #expect(root.events.hooks[CustomEvent.name] == nil)
  }

  @Test("ctx.on()")
  func ctxOn() async throws {
    let root = Context()
    let callback = Recorder<Void>()
    let handle = try root.on(CustomEvent.self) { _ in callback.record(()) }
    try root.emit(CustomEvent.self)
    #expect(callback.count == 1)
    try root.emit(CustomEvent.self)
    #expect(callback.count == 2)
    try await handle.dispose()
    try root.emit(CustomEvent.self)
    #expect(callback.count == 2)
  }

  @Test("ctx.once()")
  func ctxOnce() async throws {
    let root = Context()
    let callback = Recorder<Void>()
    let handle = try root.once(CustomEvent.self) { _ in callback.record(()) }
    try root.emit(CustomEvent.self)
    #expect(callback.count == 1)
    try root.emit(CustomEvent.self)
    #expect(callback.count == 1)
    try await handle.dispose()
    try root.emit(CustomEvent.self)
    #expect(callback.count == 1)
  }

  @Test("ctx.parallel()")
  func ctxParallel() async throws {
    let root = Context()
    try await root.parallel(CustomEvent.self)
    let callback = Recorder<Void>()
    let shouldThrow = Box(false)
    try root.intercept(FilterKey.self, true).on(CustomEvent.self) { _ in
      callback.record(())
      if shouldThrow.value { throw TestError("test") }
    }

    try await root.parallel(CustomEvent.self)
    #expect(callback.count == 1)
    try await root.parallel(scope: Session(flag: false), CustomEvent.self)
    #expect(callback.count == 1)
    try await root.parallel(scope: Session(flag: true), CustomEvent.self)
    #expect(callback.count == 2)

    // a rejecting listener must not short-circuit the others
    let settled = Box(false)
    let handle = try root.on(CustomEvent.self) { _ in
      await Task.yield()
      settled.value = true
      throw TestError("async")
    }
    shouldThrow.value = true
    do {
      try await root.parallel(CustomEvent.self)
      Issue.record("parallel did not throw")
    } catch let error as AggregateError {
      #expect(Set(error.errors.map { String(describing: $0) }) == ["test", "async"])
    }
    #expect(settled.value)
    try await handle.dispose()
  }

  @Test("ctx.emit()")
  func ctxEmit() async throws {
    let root = Context()
    try root.emit(CustomEvent.self)
    let callback = Recorder<Void>()
    let shouldThrow = Box(false)
    try root.intercept(FilterKey.self, true).on(CustomEvent.self) { _ in
      callback.record(())
      if shouldThrow.value { throw TestError("test") }
    }

    try root.emit(CustomEvent.self)
    #expect(callback.count == 1)
    try root.emit(scope: Session(flag: false), CustomEvent.self)
    #expect(callback.count == 1)
    try root.emit(scope: Session(flag: true), CustomEvent.self)
    #expect(callback.count == 2)

    shouldThrow.value = true
    expectError("test") { try root.emit(CustomEvent.self) }
  }

  @Test("ctx.serial()")
  func ctxSerial() async throws {
    let root = Context()
    try await root.serial(CustomEvent.self)
    let callback = Recorder<Void>()
    let shouldThrow = Box(false)
    try root.intercept(FilterKey.self, true).on(CustomEvent.self) { _ in
      callback.record(())
      if shouldThrow.value { throw TestError("message") }
    }

    try await root.serial(CustomEvent.self)
    #expect(callback.count == 1)
    try await root.serial(scope: Session(flag: false), CustomEvent.self)
    #expect(callback.count == 1)
    try await root.serial(scope: Session(flag: true), CustomEvent.self)
    #expect(callback.count == 2)

    shouldThrow.value = true
    await #expect(throws: TestError("message")) { try await root.serial(CustomEvent.self) }
  }

  @Test("ctx.bail()")
  func ctxBail() async throws {
    let root = Context()
    #expect(try await root.bail(WaterfallEvent.self, 1) == nil)
    let callback = Recorder<Int>()
    let shouldThrow = Box(false)
    try root.intercept(FilterKey.self, true).onBail(WaterfallEvent.self) { value in
      callback.record(value)
      if shouldThrow.value { throw TestError("message") }
      return value * 10
    }
    let fallback = Recorder<Int>()
    try root.onBail(WaterfallEvent.self) { value in
      fallback.record(value)
      return nil
    }

    #expect(try await root.bail(WaterfallEvent.self, 1) == 10)
    #expect(callback.count == 1)
    #expect(try await root.bail(scope: Session(flag: false), WaterfallEvent.self, 2) == nil)
    #expect(callback.count == 1)
    #expect(try await root.bail(scope: Session(flag: true), WaterfallEvent.self, 3) == 30)
    #expect(callback.count == 2)
    // later listeners run only when no earlier one bailed
    #expect(fallback.calls == [2])

    shouldThrow.value = true
    await #expect(throws: TestError("message")) { try await root.bail(WaterfallEvent.self, 4) }
  }

  @Test("ctx.waterfall()")
  func ctxWaterfall() async throws {
    let root = Context()
    let cb1 = Recorder<Void>()
    let cb2 = Recorder<Void>()
    let cb3 = Recorder<Void>()
    let cb4 = Recorder<Void>()
    try root.on(WaterfallEvent.self) { value, next in cb1.record(()); return value + (try await next()) }
    try root.on(WaterfallEvent.self) { value, next in cb2.record(()); return value + (try await next()) }

    #expect(try await root.waterfall(WaterfallEvent.self, 1) { 2 } == 4)
    #expect(cb1.count == 1)
    #expect(cb2.count == 1)
    cb1.reset()
    cb2.reset()

    try root.on(WaterfallEvent.self) { value, _ in cb3.record(()); return value }
    try root.on(WaterfallEvent.self) { value, next in cb4.record(()); return value + (try await next()) }
    #expect(try await root.waterfall(WaterfallEvent.self, 1) { 2 } == 3)
    #expect(cb1.count == 1)
    #expect(cb2.count == 1)
    #expect(cb3.count == 1)
    #expect(cb4.count == 0)
  }

  @Test("ctx.waterfall() rejects duplicate next()")
  func waterfallRejectsDuplicateNext() async throws {
    let root = Context()
    let terminal = Recorder<Void>()
    let callback = Recorder<Void>()
    try root.on(WaterfallEvent.self) { _, next in
      callback.record(())
      _ = try await next()
      return try await next()
    }
    await #expect(throws: CordisError.self) {
      try await root.waterfall(WaterfallEvent.self, 1) { terminal.record(()); return 2 }
    }
    #expect(callback.count == 1)
    #expect(terminal.count == 1)
  }

  @Test("ctx.waterfall() rejects continuations from outer frames")
  func waterfallRejectsOuterContinuations() async throws {
    let root = Context()
    let calls = Recorder<String>()
    let outerNext = Box<(@CordisActor () async throws -> Int)?>(nil)
    try root.on(WaterfallEvent.self) { _, next in
      outerNext.value = next
      calls.record("first")
      return try await next()
    }
    try root.on(WaterfallEvent.self) { _, next in
      calls.record("second")
      return try await next()
    }
    do {
      _ = try await root.waterfall(WaterfallEvent.self, 1) {
        calls.record("terminal")
        return try await outerNext.value!()
      }
      Issue.record("waterfall did not throw")
    } catch {
      #expect(String(describing: error) == "next() called multiple times")
    }
    #expect(calls.calls == ["first", "second", "terminal"])
  }

  @Test("ctx.waterfall() rejects duplicate next() after awaiting")
  func waterfallRejectsDuplicateNextAfterAwaiting() async throws {
    let root = Context()
    let terminal = Recorder<Void>()
    try root.on(WaterfallEvent.self) { value, next in
      let result = try await next()
      await Task.yield()
      await #expect(throws: CordisError.self) { _ = try await next() }
      return value + result
    }
    #expect(try await root.waterfall(WaterfallEvent.self, 1) { terminal.record(()); return 2 } == 3)
    #expect(terminal.count == 1)
  }

  @Test("ctx.waterfall() supports nested async calls")
  func waterfallSupportsNestedAsyncCalls() async throws {
    let root = Context()
    let terminal = Recorder<Void>()
    let callback = Recorder<Void>()
    let terminalBody: @CordisActor () async throws -> Int = { terminal.record(()); return 2 }
    try root.on(WaterfallEvent.self) { value, next in
      callback.record(())
      let result = try await next()
      if value == 1 {
        return result + (try await root.waterfall(WaterfallEvent.self, 2, terminalBody))
      }
      return result
    }
    #expect(try await root.waterfall(WaterfallEvent.self, 1, terminalBody) == 4)
    #expect(callback.count == 2)
    #expect(terminal.count == 2)
  }
}
