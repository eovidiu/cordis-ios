# Context Summary

## Active Context
- Working on: initial port of cordis core + loader + macros (plan steps 2-13)
- Blocked by: nothing
- Next: implement Sources/Cordis/Core

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

## Gotchas
- (none yet)

## Conventions
- Suite names start with the prefixes used by .harness/init.sh focused_test filters
