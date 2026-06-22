//
//  ContentView.swift
//  Narnia
//
//  Created by Leo Sheng on 2026/6/22.
//

import SwiftData
import SwiftUI

struct ContentView: View {
    let store: VaultStore
    let thumbnails: ThumbnailService
    let auth: BiometricAuthenticating

    // The app launches into the cover and only swaps to the vault after the
    // hidden door + biometric succeed. Because ContentView is the app root view,
    // this @State lives for the process lifetime and is fresh on every cold
    // launch — that's the spec's fresh-start session model. Do not persist it,
    // and do not re-lock on background/return (spec §3 rejects that).
    @State private var session = VaultSession(initiallyUnlocked: ContentView.uiTestAutoUnlock)

    // DEBUG-only test seam: a process launched WITH `-uitest-autounlock` starts
    // in the vault so XCUITests (which can't script biometrics) can reach the
    // grid. Compiled out of Release entirely, so the shipped gate is intact;
    // even in DEBUG, the gate is fully active without the launch argument.
    private static var uiTestAutoUnlock: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-uitest-autounlock")
        #else
        return false
        #endif
    }

    init(store: VaultStore,
         thumbnails: ThumbnailService,
         auth: BiometricAuthenticating = AuthService()) {
        self.store = store
        self.thumbnails = thumbnails
        self.auth = auth
    }

    var body: some View {
        if session.isUnlocked {
            NavigationStack {
                VaultGridView(folderID: nil, store: store, thumbnails: thumbnails)
            }
            // Explicit, thumb-reachable quick-exit ("panic"): locking the session
            // swaps this whole vault subtree out for the cover, which collapses
            // folder navigation and dismisses any presented viewer in one move.
            // Only visible inside the unlocked vault, so it never affects the
            // disguise. No automatic/scenePhase relock — only this tap locks.
            .overlay(alignment: .bottomTrailing) {
                Button {
                    session.lock()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .frame(width: 44, height: 44)
                        .background(.thinMaterial, in: Circle())
                }
                .padding()
                .accessibilityIdentifier("vaultExitButton")
                .accessibilityLabel("Exit")
            }
        } else {
            CoverView(onHiddenDoor: {
                Task {
                    await session.attemptUnlock(
                        using: auth,
                        reason: "Authenticate to continue.")
                }
            })
        }
    }
}

#Preview {
    let container = try! ModelContainer(
        for: VaultItem.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let storage = try! VaultStorage(
        root: FileManager.default.temporaryDirectory
            .appending(path: "VaultPreview-\(UUID().uuidString)"))
    let store = VaultStore(context: container.mainContext, storage: storage)
    return ContentView(store: store,
                       thumbnails: ThumbnailService(thumbsDirectory: storage.thumbsDir))
        .modelContainer(container)
}
