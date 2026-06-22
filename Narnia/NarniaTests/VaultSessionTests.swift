//
//  VaultSessionTests.swift
//  NarniaTests
//
//  Unit tests for VaultSession — the fresh-start security gate (design spec §3).
//
//  These are the security-critical tests: the vault must start locked, unlock
//  ONLY on a successful authentication, and — being one-way — must never
//  re-lock, including after a failed attempt against an already-open vault.
//

import Foundation
import Testing
@testable import Narnia

/// Deterministic ``BiometricAuthenticating`` returning a fixed result, so the
/// gate's logic can be tested without the LocalAuthentication prompt.
private struct FakeAuth: BiometricAuthenticating {
    let result: Bool
    func authenticate(reason: String) async -> Bool { result }
}

@MainActor
struct VaultSessionTests {

    @Test
    func freshSessionStartsLocked() {
        let session = VaultSession()
        #expect(session.isUnlocked == false)
    }

    @Test
    func successfulAuthUnlocks() async {
        let session = VaultSession()
        await session.attemptUnlock(using: FakeAuth(result: true), reason: "test")
        #expect(session.isUnlocked == true)
    }

    @Test
    func failedAuthLeavesLocked() async {
        let session = VaultSession()
        await session.attemptUnlock(using: FakeAuth(result: false), reason: "test")
        #expect(session.isUnlocked == false)
    }

    @Test
    func failedAttemptNeverRelocks() async {
        let session = VaultSession()
        session.unlock()
        // A failed attempt against an already-open vault must not re-lock it.
        await session.attemptUnlock(using: FakeAuth(result: false), reason: "test")
        #expect(session.isUnlocked == true)
    }

    @Test
    func explicitLockReturnsToLocked() {
        let session = VaultSession()
        session.unlock()
        session.lock()
        #expect(session.isUnlocked == false)
    }

    @Test
    func lockIsIdempotent() {
        let session = VaultSession()
        session.unlock()
        session.lock()
        session.lock()
        #expect(session.isUnlocked == false)
    }

    @Test
    func lockThenUnlockWorksAgain() async {
        let session = VaultSession()
        session.unlock()
        session.lock()
        // The explicit quick-exit is the one allowed inverse; re-authentication
        // must still open the vault again afterwards.
        await session.attemptUnlock(using: FakeAuth(result: true), reason: "test")
        #expect(session.isUnlocked == true)
    }
}
