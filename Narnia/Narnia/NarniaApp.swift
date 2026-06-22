//
//  NarniaApp.swift
//  Narnia
//
//  Created by Leo Sheng on 2026/6/22.
//

import SwiftData
import SwiftUI

@main
struct NarniaApp: App {
    /// The single shared SwiftData container backing the vault. Its `mainContext`
    /// is handed to `VaultStore`, and the same container is injected into the view
    /// environment so `VaultGridView`'s `@Query` reads from the identical store.
    let container: ModelContainer
    let store: VaultStore
    let thumbnails: ThumbnailService

    init() {
        do {
            // Creates Vault/ (+ files/, thumbs/) with NSFileProtectionComplete.
            let storage = try VaultStorage()
            // Co-locate the SwiftData store inside Vault/ so it inherits the
            // directory's complete-protection class.
            let config = ModelConfiguration(url: storage.root.appending(path: "Narnia.store"))
            let container = try ModelContainer(for: VaultItem.self, configurations: config)
            self.container = container
            self.store = VaultStore(context: container.mainContext, storage: storage)
            self.thumbnails = ThumbnailService(thumbsDirectory: storage.thumbsDir)
        } catch {
            // Launch-critical: without the vault container there is no app.
            fatalError("Failed to initialize vault store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(store: store, thumbnails: thumbnails)
                .modelContainer(container)
        }
    }
}
