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

    init(store: VaultStore, thumbnails: ThumbnailService) {
        self.store = store
        self.thumbnails = thumbnails
    }

    var body: some View {
        NavigationStack {
            VaultGridView(folderID: nil, store: store, thumbnails: thumbnails)
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
