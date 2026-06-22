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

import Observation

/// User's standing choice for removing an imported file's ORIGINAL (best-effort).
///
/// `CaseIterable` so a settings `Picker` can iterate the available choices.
enum OriginalsDisposition: String, Sendable, CaseIterable {
    case ask     // not yet decided — prompt on first import
    case remove  // attempt to remove originals when possible
    case keep    // never remove originals
}

/// Reads and persists the user's ``OriginalsDisposition`` via `UserDefaults`.
///
/// Defaults to `.ask` when no choice has been recorded (or a stored value is
/// unrecognized). Writes are flushed to the backing store immediately on set.
///
/// `@Observable` so SwiftUI views (e.g. the settings screen) track changes to
/// ``disposition`` and the flags derived from it. Because `@Observable` only
/// instruments *stored* properties, ``disposition`` is backed by a stored
/// property — seeded from `UserDefaults` in `init` and mirrored back to the
/// store in its `didSet` — rather than computed directly over `UserDefaults`.
@MainActor @Observable
final class OriginalsPreference {

    /// Stable `UserDefaults` key for the persisted disposition.
    @ObservationIgnored
    private static let key = "vault.originalsDisposition"

    @ObservationIgnored
    private let defaults: UserDefaults

    /// Current disposition; persisted to `UserDefaults` on set.
    ///
    /// Seeded from the store at `init`; an absent or unrecognized stored value
    /// yields `.ask`. Each change is written straight back to `UserDefaults`.
    var disposition: OriginalsDisposition {
        didSet {
            defaults.set(disposition.rawValue, forKey: Self.key)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if
            let raw = defaults.string(forKey: Self.key),
            let value = OriginalsDisposition(rawValue: raw)
        {
            self.disposition = value
        } else {
            self.disposition = .ask
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
