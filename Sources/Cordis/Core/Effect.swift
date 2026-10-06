/// Undoes one effect. Sync cordis disposers are the degenerate case.
public typealias Disposer = @CordisActor @Sendable () async throws -> Void

/// Debug description of a live effect (`fiber.getEffects()`).
public struct EffectMeta: Sendable, Equatable {
  public let label: String
  public var children: [EffectMeta]

  public init(label: String, children: [EffectMeta] = []) {
    self.label = label
    self.children = children
  }
}

/// Collects the disposers of a running effect or plugin. Each `collect` is
/// one `yield` of a cordis effect generator: the disposer is recorded, and if
/// the owner was disposed in the meantime `collect` then throws
/// `EffectAbortedError` so the body stops at that point.
@CordisActor
public final class EffectScope {
  private let onCollect: (@escaping Disposer) -> Void
  private let onCollectHandle: (EffectHandle) -> Void
  private let isAborted: () -> Bool

  init(
    collect: @escaping (@escaping Disposer) -> Void,
    collectHandle: @escaping (EffectHandle) -> Void,
    isAborted: @escaping () -> Bool
  ) {
    self.onCollect = collect
    self.onCollectHandle = collectHandle
    self.isAborted = isAborted
  }

  /// Records `dispose`; throws `EffectAbortedError` if the owner was disposed.
  public func collect(_ dispose: @escaping Disposer) throws {
    onCollect(dispose)
    if isAborted() { throw EffectAbortedError() }
  }

  /// Adopts a child effect (e.g. the handle returned by `ctx.on`): it is
  /// disposed with this scope and listed under it in `getEffects()`.
  public func collect(_ handle: EffectHandle) throws {
    onCollectHandle(handle)
    if isAborted() { throw EffectAbortedError() }
  }
}

/// A live effect created by `ctx.effect`, `ctx.on`, `ctx.provide`, …
@CordisActor
public final class EffectHandle {
  public let label: String
  var children: [EffectHandle] = []
  var disposers: [Disposer] = []
  var armed = true
  var task: Task<Void, any Error>?
  var fiberToken: UInt64?

  init(label: String) {
    self.label = label
  }

  public var meta: EffectMeta {
    EffectMeta(label: label, children: children.map(\.meta))
  }

  public var isDisposed: Bool { !armed }

  /// Waits for an async effect body to finish (cordis `await ctx.effect(...)`)
  /// and rethrows its error. Returns immediately for sync effects.
  public func ready() async throws {
    try await task?.value
  }

  /// Disposes the effect: waits for a running body, then runs the collected
  /// disposers newest first, one at a time. Idempotent. Every disposer runs;
  /// the first error is rethrown.
  public func dispose() async throws {
    guard armed else { return }
    armed = false
    if let task { _ = await task.result }
    try await runDisposers()
  }

  func runDisposers() async throws {
    let list = disposers.reversed()
    disposers.removeAll()
    var firstError: (any Error)?
    for dispose in list {
      do {
        try await dispose()
      } catch {
        if firstError == nil { firstError = error }
      }
    }
    if let firstError { throw firstError }
  }
}

/// An entry of `fiber.disposables`: an effect handle, or a bare disposer
/// collected by a plugin's `apply`.
enum FiberDisposable {
  case handle(EffectHandle)
  case disposer(Disposer)

  @CordisActor
  func run() async throws {
    switch self {
    case .handle(let handle): try await handle.dispose()
    case .disposer(let dispose): try await dispose()
    }
  }
}

extension Fiber {
  /// Runs `execute` synchronously; a returned disposer runs when the effect
  /// is disposed (cordis: a function returning a disposer).
  @discardableResult
  public func effect(_ label: String = "anonymous", sync execute: () throws -> Disposer?) throws -> EffectHandle {
    try effect(label, scoped: { scope in
      if let dispose = try execute() { try scope.collect(dispose) }
    })
  }

  /// Runs `execute` synchronously with a scope (cordis: a sync generator).
  /// If it throws, the disposers collected so far run and the error is
  /// rethrown.
  @discardableResult
  public func effect(_ label: String = "anonymous", scoped execute: (EffectScope) throws -> Void) throws -> EffectHandle {
    try assertActive()
    let handle = EffectHandle(label: label)
    let scope = makeScope(for: handle)
    do {
      try execute(scope)
    } catch is EffectAbortedError {
      // a sync body cannot be aborted before it returns
    } catch {
      handle.armed = false
      let logger = ctx.logger
      Task { @CordisActor in
        do { try await handle.runDisposers() } catch { logger.error(error) }
      }
      throw error
    }
    attach(handle)
    return handle
  }

  /// Runs `execute` as a task on `CordisActor` (cordis: async function or
  /// async generator). Disposing waits for the body; a `collect` after
  /// disposal throws `EffectAbortedError`, ending the body. If the body
  /// throws, the effect is disposed, the error is logged, and `ready()`
  /// rethrows it.
  @discardableResult
  public func effect(
    _ label: String = "anonymous",
    _ execute: @escaping @CordisActor @Sendable (EffectScope) async throws -> Void
  ) throws -> EffectHandle {
    try assertActive()
    let handle = EffectHandle(label: label)
    let scope = makeScope(for: handle)
    let logger = ctx.logger
    handle.task = Task { @CordisActor in
      do {
        try await execute(scope)
      } catch is EffectAbortedError {
        return
      } catch {
        handle.armed = false
        do { try await handle.runDisposers() } catch { logger.error(error) }
        logger.error(error)
        throw error
      }
    }
    attach(handle)
    return handle
  }

  public func getEffects() -> [EffectMeta] {
    disposables.values.compactMap {
      if case .handle(let handle) = $0 { return handle.meta }
      return nil
    }
  }

  private func makeScope(for handle: EffectHandle) -> EffectScope {
    EffectScope(
      collect: { dispose in handle.disposers.append(dispose) },
      collectHandle: { [self] child in
        handle.disposers.append { try await child.dispose() }
        handle.children.append(child)
        if let token = child.fiberToken {
          disposables.delete(token)
          child.fiberToken = nil
        }
      },
      isAborted: { !handle.armed }
    )
  }

  private func attach(_ handle: EffectHandle) {
    let token = disposables.push(.handle(handle))
    handle.fiberToken = token
    handle.disposers.append { [self] in
      if handle.fiberToken == token {
        disposables.delete(token)
        handle.fiberToken = nil
      }
    }
  }
}
