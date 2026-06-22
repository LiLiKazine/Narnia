# Narnia

A private, encrypted file vault for iOS, disguised as an ordinary app. Currently
early-stage: a SwiftUI project skeleton plus the design spec.

## Source of truth

**`narnia-vault-design.md`** (repo root) is the authoritative design. Read it
before implementing vault behavior — it records deliberate decisions and their
tradeoffs (e.g. the fresh-start-only session model). Don't silently deviate.

## Commands

The Xcode project lives in the `Narnia/` subdirectory, not the repo root — `cd`
there first. Pick a simulator from `xcrun simctl list devices available`.

```bash
cd Narnia

# Build
xcodebuild -project Narnia.xcodeproj -scheme Narnia \
  -destination 'platform=iOS Simulator,name=iPhone 16' build

# Test (runs both NarniaTests and NarniaUITests)
xcodebuild -project Narnia.xcodeproj -scheme Narnia \
  -destination 'platform=iOS Simulator,name=iPhone 16' test
```

## Conventions

- **SwiftUI**, no UIKit unless an API requires it. iOS deployment target **26.5**.
- **Unit tests use Swift Testing** (`import Testing`, `@Test`, `#expect`) — not
  XCTest. **UI tests use XCTest** (`XCTestCase`). Match the framework already in
  the target you're editing.
- Vault data lives in the app's own encrypted container, kept entirely separate
  from cover/closet data — the two must never reference each other.

## Tech decisions

- **iOS app, SwiftUI, Swift 6 language mode.** UI is SwiftUI; no UIKit unless a
  capability is unavailable in SwiftUI.
- **Swift Concurrency over GCD.** Use `async`/`await`, `Task`, and structured
  concurrency for parallelism — not `DispatchQueue`/GCD.
- **Actors over locks for data safety.** Protect shared mutable state with `actor`
  isolation (and `@MainActor` for UI state), not `NSLock`/`os_unfair_lock`/serial queues.

## Gotchas

- **Git/SSH identity is repo-local.** This repo uses the `github-lilikazine` SSH
  host alias (commits as `Leo Sheng <lilikazine@gmail.com>`), set via
  `git config --local`. The global config is a different identity — don't rely on
  it, and don't push through plain `github.com` (auth fails as the wrong user).
- Xcode per-user files (`xcuserdata/`, `*.xcuserstate`) are gitignored — keep
  them out of commits.
