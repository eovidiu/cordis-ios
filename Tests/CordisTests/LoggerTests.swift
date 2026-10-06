import Testing
@testable import Cordis

@Suite("LoggerTests")
@CordisActor
struct LoggerTests {
  private func setup() throws -> (Context, Recorder<LogMessage>) {
    let ctx = Context()
    let captured = Recorder<LogMessage>()
    try ctx.logger.exporter(ClosureExporter(level: .debug) { captured.record($0) })
    return (ctx, captured)
  }

  @Test("keeps the bounded buffer in place and chronological")
  func boundedBuffer() {
    let ctx = Context()
    ctx.logger.bufferSize = 2
    ctx.logger.info("one")
    ctx.logger.info("two")
    ctx.logger.info("three")
    #expect(ctx.logger.buffer.map(\.text) == ["two", "three"])

    ctx.logger.bufferSize = 1
    ctx.logger.info("four")
    #expect(ctx.logger.buffer.map(\.text) == ["four"])

    ctx.logger.bufferSize = 0
    ctx.logger.info("five")
    #expect(ctx.logger.buffer.isEmpty)
  }

  @Test("disposes the exporter that registered the disposer")
  func disposesOwnExporter() async throws {
    let ctx = Context()
    let first = Recorder<LogMessage>()
    let second = Recorder<LogMessage>()
    let disposeFirst = try ctx.logger.exporter(ClosureExporter { first.record($0) })
    let disposeSecond = try ctx.logger.exporter(ClosureExporter { second.record($0) })

    try await disposeFirst.dispose()
    ctx.logger.info("test")
    #expect(first.count == 0)
    #expect(second.count == 1)

    try await disposeSecond.dispose()
    ctx.logger.info("test")
    #expect(second.count == 1)
  }

  @Test("uses fiber name when called from outside any service")
  func usesFiberName() throws {
    let (ctx, captured) = try setup()
    ctx.logger.debug("hello")
    #expect(captured.calls.map(\.name) == ["root"])
  }

  @Test("honours explicit name argument")
  func honoursExplicitName() throws {
    let (ctx, captured) = try setup()
    ctx.logger.named("custom").debug("hello")
    #expect(captured.calls.map(\.name) == ["custom"])
  }

  @Test("honours intercept name")
  func honoursInterceptName() throws {
    let (ctx, captured) = try setup()
    ctx.intercept(LoggerIntercept.self, .init(name: "intercepted")).logger.debug("hello")
    #expect(captured.calls.map(\.name) == ["intercepted"])
  }
}
