# 2026-06-22-06: Hidden-door entry + biometric auth (fresh-start session)

**Status:** Implemented — completes roadmap item "Hidden-door entry + biometric auth".

## Context

Until now the app launched straight into the vault. Spec §3 requires the app to
masquerade as an ordinary app (the cover) and reveal the vault only via a hidden
long-press + Face/Touch ID, with a deliberate FRESH-START-ONLY session. Iteration 7
of the autonomous dev loop (team lead + 3-agent swarm + a debug-fix for the UI-test
regression the new gate caused).

## Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| Root inversion | `ContentView` gates cover↔vault on `session.isUnlocked` | Single root that swaps; vault stack unchanged underneath |
| Session lifetime | `@State VaultSession` on the root view, NOT persisted | Lives for the process, resets on cold launch — the fresh-start model with no extra machinery |
| Auth seam | `BiometricAuthenticating` protocol + concrete `AuthService` (LAContext) | Lets a fake drive success/failure so the security gate (`attemptUnlock`) is unit-testable without a real biometric |
| Biometric policy | `.deviceOwnerAuthenticationWithBiometrics`, fallback to `.deviceOwnerAuthentication` | Face/Touch ID first, passcode fallback — matches §3's accepted "reduces to device passcode" tradeoff |
| Cover scope | deliberately minimal wardrobe disguise (Outerwear/Tops/Shoes) | The cover's full product design isn't in this repo; build a plausible minimum, don't over-invest |
| UI-test reachability | `#if DEBUG` + `-uitest-autounlock` launch arg → `VaultSession(initiallyUnlocked:)` | Lets the vault UI test run; compiled out of Release so it cannot weaken the shipped gate |

## What Changed

- `Vault/VaultSession.swift` (new) — `@MainActor @Observable`; `isUnlocked` (private(set), default false, not persisted); `unlock()` (one-way); `attemptUnlock(using:reason:)` (unlock only on auth success); additive `init(initiallyUnlocked:)`.
- `Vault/AuthService.swift` (new) — `BiometricAuthenticating` protocol + `AuthService` (fresh LAContext per call, biometrics-first w/ passcode fallback, callback wrapped in a continuation, returns false on any error/cancel).
- `Cover/CoverView.swift` (new) — minimal disguise; Outerwear tab ends in a wooden back-panel whose long-press fires `onHiddenDoor`; references no vault types; no unlock/vault/Face-ID hints.
- `ContentView.swift` (modified) — root gate: cover by default, vault when unlocked; injects `auth` (default `AuthService()`); wires the long-press to `session.attemptUnlock`.
- `project.pbxproj` — `NSFaceIDUsageDescription` (app target Debug+Release).
- `VaultGridUITests.swift` (modified) — passes the DEBUG auto-unlock arg to reach the vault.
- `VaultSessionTests.swift` (new) — fresh-locked / success-unlocks / failure-stays-locked / no-relock gate tests.
- `README.md` — ticked "Hidden-door entry + biometric auth".

## What Was Discovered

- **Inverting the root broke the existing vault UI test** — it expected the grid at launch but now hits the cover, and biometrics can't be scripted in the simulator. Solved with a `#if DEBUG`-only launch-arg auto-unlock seam (inert in Release, verified by review), not by weakening the gate.
- **Fresh-start = no machinery** — modeling the session as root `@State` gives the exact spec behavior (locked on cold launch, stays unlocked across backgrounding) for free. Both reviewers confirmed there is NO re-lock path, NO scenePhase/snapshot/Face-ID-on-return code, and NO Release path to the vault without a successful biometric.
- **Biometric lockout silently degrades to passcode** (the fallback policy) — consistent with §3's documented tradeoff; recorded as a conscious choice, not a bug.
- **AuthService isn't unit-tested directly** (it wraps LocalAuthentication — that's exactly why `BiometricAuthenticating` was abstracted); the security gate logic in `VaultSession` is fully covered via the fake.
- Cover is intentionally minimal — the spec's whole-product/cover design lives in a doc not in this repo; recorded so it isn't mistaken for the final disguise.
