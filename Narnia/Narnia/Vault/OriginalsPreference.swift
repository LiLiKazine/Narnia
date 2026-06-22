//
//  OriginalsPreference.swift
//  Narnia
//
//  Persisted "remove originals when possible" preference (design spec §2).
//
//  At the first import the user is asked, once, whether Narnia should attempt
//  to remove the ORIGINAL of an imported file (best-effort, where the platform
//  permits). The choice is saved and later changeable from the settings screen
//  (a separate roadmap item). This type owns only the persisted value — the
//  prompt UI and import wiring live elsewhere.
//

import Foundation

/// User's standing choice for removing an imported file's ORIGINAL (best-effort).
enum OriginalsDisposition: String, Sendable {
    case ask     // not yet decided — prompt on first import
    case remove  // attempt to remove originals when possible
    case keep    // never remove originals
}

/// Reads and persists the user's ``OriginalsDisposition`` via `UserDefaults`.
///
/// Defaults to `.ask` when no choice has been recorded (or a stored value is
/// unrecognized). Writes are flushed to the backing store immediately on set.
@MainActor
final class OriginalsPreference {

    /// Stable `UserDefaults` key for the persisted disposition.
    private static let key = "vault.originalsDisposition"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Current disposition; persisted to `UserDefaults` on set.
    ///
    /// Reading an absent or unrecognized stored value yields `.ask`.
    var disposition: OriginalsDisposition {
        get {
            guard
                let raw = defaults.string(forKey: Self.key),
                let value = OriginalsDisposition(rawValue: raw)
            else {
                return .ask
            }
            return value
        }
        set {
            defaults.set(newValue.rawValue, forKey: Self.key)
        }
    }

    /// True once the user has made a choice (disposition != `.ask`).
    var hasBeenAsked: Bool {
        disposition != .ask
    }

    /// Should we attempt removal right now? (disposition == `.remove`)
    var shouldRemove: Bool {
        disposition == .remove
    }
}
