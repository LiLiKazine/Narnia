//
//  SettingsView.swift
//  Narnia
//
//  The Realm settings screen: summoned from inside the unlocked vault by the
//  gear control. Its only confirmed inhabitant today is the originals
//  preference (design spec §5) — the same persisted choice the import flow
//  honors, so changing it here changes the next import's behavior. Future
//  security toggles (hide names, flip-to-lock) will move in alongside it; their
//  structure is stubbed below but deliberately not implemented (separate
//  roadmap items).
//

import SwiftUI

/// The vault's settings screen. Edits the *shared* ``OriginalsPreference`` so a
/// change here is the same source of truth the next import reads.
struct SettingsView: View {
    /// The single shared preference, threaded down from the vault root. Bindable
    /// so the Picker reads/writes `disposition` directly; the write is persisted
    /// by `OriginalsPreference` itself.
    @Bindable var preference: OriginalsPreference

    @Environment(\.dismiss) private var dismiss

    init(preference: OriginalsPreference) {
        self.preference = preference
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Remove originals", selection: $preference.disposition) {
                        Text("Ask each time").tag(OriginalsDisposition.ask)
                        Text("Remove when possible").tag(OriginalsDisposition.remove)
                        Text("Keep originals").tag(OriginalsDisposition.keep)
                    }
                    .accessibilityIdentifier("originalsPicker")
                } header: {
                    Text("Imports")
                } footer: {
                    Text(
                        "When you import a file, Narnia can remove the original "
                            + "from its source on a best-effort basis — only where "
                            + "the platform permits, and you'll still confirm any "
                            + "Photos deletion."
                    )
                }

                // MARK: Security (placeholder — FUTURE)
                //
                // Future home for vault security toggles per spec §5: "Hide
                // names" and opt-in "flip-to-lock". These are separate roadmap
                // items and are intentionally NOT implemented here yet — leave
                // this section structure as the landing spot when they arrive.
                // (No rows on purpose; an empty Section renders nothing.)
                Section("Security") {
                    // Intentionally empty for now.
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("settingsDoneButton")
                }
            }
        }
    }
}

#Preview {
    SettingsView(preference: OriginalsPreference())
}
