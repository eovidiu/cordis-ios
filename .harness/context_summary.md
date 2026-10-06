# Context Summary

## Active Context
- Working on: nothing (initial port complete)
- Blocked by: nothing
- Next: new features as requested

## Decisions
- Port target: cordiverse/cordis commit f8ea3cd (cordis@4.0.0-rc.10), paper arXiv 2608.25512: TypeScript source is the behavioural spec (2026-10)
- Swift 6 language mode, strict concurrency, iOS 17 / macOS 14, Swift Testing (2026-10)
- One global actor `CordisActor` replaces the JS thread; Context/Fiber/services/Loader are @CordisActor classes; lifecycle transitions are Tasks stored in `fiber.inertia` (2026-10)
- No Proxy port: services are read through typed keys `ctx[Key.self]`, Algorithm 6 lives in that subscript; proxy-only tests dropped (2026-10)
- Typed keys (`ServiceKey`, `EventKey`, `InterceptKey`) carry `static name` used as the runtime string key (2026-10)
- Realms (`Realm` struct minted per root) replace Symbols for isolation (2026-10)
- Disposers are `@CordisActor () async throws -> Void` (2026-10)
- Listener bail rule: non-nil result bails; Swift has no `false` (2026-10)
- Config: `Decodable & Sendable` + optional `validate`; errors are `ValidationError` with cordis message format (2026-10)
- Logger is required by the core error boundaries; minimal port (2026-10)
- `ctx.on` listeners return Void and never bail; bail-capable listeners use `ctx.onBail`: one `on` with both shapes was ambiguous for multi-statement closures (2026-10)
- `emit` is synchronous (internal status/plugin/service events fire from sync code); async listeners under emit run as logged tasks (2026-10)
- Fiber unload runs disposers sequentially, newest first: Swift cannot start a task synchronously on iOS 17, and sequential keeps cordis's cross-fiber ordering (test "update config while injected service reloads") (2026-10)
- `Plugin` is a @CordisActor protocol so plugins can hold mutable state; @Plugin/@Service require an explicit @CordisActor on the class (macros cannot add it; diagnostic enforces it) (2026-10)
- Demo logic lives in library target CordisDemoKit: testing an executable target raced in clean builds ("no such module CordisDemo") (2026-10)

## Gotchas
- A trailing closure without `await` passed to `ctx.effect { }` selects the sync `scoped:` overload; JS "async" effects without awaits must `await Task.yield()` to get async semantics
- Synthesized Decodable ignores property defaults: plugin configs decoded from `{}` need optional fields
- Swift Testing + `assertMacroExpansion`: use SwiftSyntaxMacrosGenericTestSupport with `failureHandler: Issue.record`; the XCTest variant does not fail Swift Testing tests

## Conventions
- Suite names start with the prefixes used by .harness/init.sh focused_test filters
