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

    /// Privacy setting (design spec §5): genericizes on-screen folder/document
    /// captions to plug the text leak from item names. `@AppStorage`-backed so
    /// this toggle and the readers (the cell + the folder nav title) share one
    /// observed source of truth without threading an object.
    @AppStorage("vault.hideNames") private var hideNames = false

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

                // MARK: Security (spec §5)
                //
                // "Hide names" lives here. Opt-in "flip-to-lock" is a separate
                // roadmap item and still belongs in this section when it lands.
                Section {
                    Toggle("Hide names", isOn: $hideNames)
                        .accessibilityIdentifier("hideNamesToggle")
                } header: {
                    Text("Security")
                } footer: {
                    Text(
                        "Hides folder and document names in the grid to avoid "
                            + "showing identifying text. Documents are normally "
                            + "identified only by their name, so they'll appear "
                            + "as generic items while this is on."
                    )
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
