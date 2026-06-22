//
//  AuthService.swift
//  Narnia
//
//  Real biometric authentication via LocalAuthentication (design spec §3).
//
//  The concrete ``BiometricAuthenticating`` used in production: it puts up the
//  system Face ID / Touch ID prompt, falling back to the device passcode where
//  biometrics are unavailable. Stateless, so it's trivially `Sendable`; tests
//  use a fake instead of this type.
//

import Foundation
import LocalAuthentication

/// Real biometric auth via LocalAuthentication. Stateless → `Sendable`.
struct AuthService: BiometricAuthenticating {

    init() {}

    /// Prompts for Face/Touch ID, or the device passcode if biometrics aren't
    /// available, and reports whether authentication succeeded.
    ///
    /// Uses a FRESH `LAContext` per call (a context caches its evaluation, so
    /// reusing one would let a prior success satisfy a later prompt). Prefers
    /// biometrics-only; if that policy can't be evaluated, falls back to
    /// `.deviceOwnerAuthentication` (biometrics-or-passcode). Any thrown error,
    /// user cancel, or denied evaluation resolves to `false`.
    func authenticate(reason: String) async -> Bool {
        let context = LAContext()

        // Biometrics-first; fall back to biometrics-or-passcode when biometrics
        // can't be evaluated (no enrolled face/finger, hardware lockout, etc.).
        var policy: LAPolicy = .deviceOwnerAuthenticationWithBiometrics
        if !context.canEvaluatePolicy(policy, error: nil) {
            policy = .deviceOwnerAuthentication
        }

        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(policy, localizedReason: reason) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }
}
