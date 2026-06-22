//
//  OriginalsPreferenceTests.swift
//  NarniaTests
//
//  Unit tests for OriginalsPreference: default value, derived flags, and
//  persistence across instances.
//

import Foundation
import Testing
@testable import Narnia

@MainActor
struct OriginalsPreferenceTests {

    // MARK: - Fixture

    /// Builds a preference backed by a freshly-cleared, uniquely-named
    /// `UserDefaults` suite, and a teardown closure that removes it. Keeps
    /// tests isolated from `.standard` and from each other.
    private func makeSuite(
        function: String = #function
    ) -> (defaults: UserDefaults, teardown: () -> Void) {
        let suiteName = "test.originals.\(function).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, { defaults.removePersistentDomain(forName: suiteName) })
    }

    // MARK: - Tests

    @Test
    func freshInstanceDefaultsToAsk() {
        let (defaults, teardown) = makeSuite()
        defer { teardown() }

        let preference = OriginalsPreference(defaults: defaults)

        #expect(preference.disposition == .ask)
        #expect(preference.hasBeenAsked == false)
        #expect(preference.shouldRemove == false)
    }

    @Test
    func settingRemovePersistsAcrossInstances() {
        let (defaults, teardown) = makeSuite()
        defer { teardown() }

        let preference = OriginalsPreference(defaults: defaults)
        preference.disposition = .remove

        #expect(preference.shouldRemove == true)
        #expect(preference.hasBeenAsked == true)

        // A new instance on the same suite reads the persisted value.
        let reloaded = OriginalsPreference(defaults: defaults)
        #expect(reloaded.disposition == .remove)
        #expect(reloaded.shouldRemove == true)
        #expect(reloaded.hasBeenAsked == true)
    }

    @Test
    func unrecognizedStoredValueDefaultsToAsk() {
        let (defaults, teardown) = makeSuite()
        defer { teardown() }

        // Simulate a corrupt / future-version value under the live key.
        defaults.set("garbage", forKey: "vault.originalsDisposition")

        let preference = OriginalsPreference(defaults: defaults)

        #expect(preference.disposition == .ask)
        #expect(preference.hasBeenAsked == false)
        #expect(preference.shouldRemove == false)
    }

    @Test
    func settingKeepPersistsAcrossInstances() {
        let (defaults, teardown) = makeSuite()
        defer { teardown() }

        let preference = OriginalsPreference(defaults: defaults)
        preference.disposition = .keep

        #expect(preference.shouldRemove == false)
        #expect(preference.hasBeenAsked == true)

        // A new instance on the same suite reads the persisted value.
        let reloaded = OriginalsPreference(defaults: defaults)
        #expect(reloaded.disposition == .keep)
        #expect(reloaded.shouldRemove == false)
        #expect(reloaded.hasBeenAsked == true)
    }
}
