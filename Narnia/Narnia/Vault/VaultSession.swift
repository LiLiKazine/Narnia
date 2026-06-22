//
//  VaultSession.swift
//  Narnia
//
//  The "fresh start only" session model (design spec §3).
//
//  Authentication happens ONCE per app lifetime. After the hidden door unlocks
//  the vault, it stays unlocked for the rest of the PROCESS LIFETIME — no
//  auto-relock on background, app-switch, notification, or screen lock. Because
//  the unlocked state is never persisted, a cold launch starts locked again.
//
//  This file owns the session gate and the auth abstraction the gate calls; the
//  concrete biometric implementation lives in AuthService.swift, and the cover
//  UI / root gating that drive this session are built elsewhere.
//

import Foundation

/// Biometric (Face/Touch ID) gate with passcode fallback. Abstracted behind a
/// protocol so tests can substitute a fake without touching LocalAuthentication.
protocol BiometricAuthenticating: Sendable {
    /// Prompts the user; returns `true` only on a confirmed successful
    /// authentication. Never throws — any failure, cancellation, or error
    /// surfaces as `false`.
    func authenticate(reason: String) async -> Bool
}

/// The fresh-start session: the vault is locked at cold launch and, once
/// unlocked, stays unlocked for the PROCESS LIFETIME (spec §3 — no auto-relock
/// on background). Not persisted, so a cold launch starts locked again.
@MainActor
@Observable
final class VaultSession {

    /// Whether the vault is currently open. Starts `false` (locked) and only
    /// ever transitions to `true` — never back, for the life of the process.
    private(set) var isUnlocked: Bool

    /// Creates a session. Defaults to locked (`false`), preserving the
    /// fresh-start model: a cold launch always starts locked. The parameter is
    /// an additive seam — production code uses the default; only a DEBUG UI-test
    /// path passes `true` to start pre-unlocked (see `ContentView`).
    init(initiallyUnlocked: Bool = false) {
        self.isUnlocked = initiallyUnlocked
    }

    /// Opens the vault. One-way and idempotent: once unlocked, the session
    /// stays unlocked until the process terminates. Deliberately has no inverse
    /// (spec §3 explicitly decides against re-locking on background/return).
    func unlock() {
        isUnlocked = true
    }

    /// Explicit, user-initiated quick-exit ("panic"): leaves the vault back to the
    /// cover. This is the DELIBERATE exception to the otherwise one-way session —
    /// `unlock()` remains one-way for the automatic path (spec §3 rejects AUTOMATIC
    /// relock on background; this is an explicit user action, which is allowed).
    func lock() { isUnlocked = false }

    /// Authenticate via `auth`; unlock ONLY on success. The single entry point
    /// the hidden door calls — this is the security gate and is unit-tested.
    ///
    /// A failed attempt leaves the current state untouched, so it can never
    /// re-lock an already-open vault.
    func attemptUnlock(using auth: BiometricAuthenticating, reason: String) async {
        if await auth.authenticate(reason: reason) {
            unlock()
        }
    }
}
