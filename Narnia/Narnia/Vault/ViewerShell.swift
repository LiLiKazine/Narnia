//
//  ViewerShell.swift
//  Narnia
//
//  The common swipe-between-items viewer (spec §1). A full-screen paging
//  container that wraps the three type-specific views — PhotoView,
//  HardenedVideoView, QuickLookView — and routes each item to the right one by
//  `kind`. Opened from the grid at the tapped item; swiping pages across the
//  folder's non-folder items in display order.
//

import SwiftUI

/// Full-screen, swipe-between-items viewer. Pages across `items` and routes
/// each to its type-specific view, starting at `startID`.
struct ViewerShell: View {
    /// The folder's NON-folder items, in display order. One page each.
    let items: [VaultItem]
    /// Metadata + file-URL resolution. `@MainActor`, safe from this view.
    let store: VaultStore

    /// The currently shown item's id, bound to the paging `TabView`.
    @State private var currentID: UUID

    @Environment(\.dismiss) private var dismiss

    init(items: [VaultItem], startID: UUID, store: VaultStore) {
        self.items = items
        self.store = store
        _currentID = State(initialValue: startID)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black
                .ignoresSafeArea()

            TabView(selection: $currentID) {
                ForEach(items) { item in
                    page(for: item)
                        .tag(item.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            closeButton
        }
    }

    /// Routes a single item to its type-specific view by `kind`. A nil file URL
    /// (or an unexpected folder) shows a neutral placeholder — never any text
    /// that could leak the item's contents.
    @ViewBuilder
    private func page(for item: VaultItem) -> some View {
        if let fileURL = store.fileURL(for: item) {
            switch item.kind {
            case .photo:
                PhotoView(fileURL: fileURL)
            case .video:
                HardenedVideoView(fileURL: fileURL)
            case .document, .other:
                QuickLookView(fileURL: fileURL)
            case .folder:
                // Items are pre-filtered to non-folders; this can't occur.
                placeholder
            }
        } else {
            placeholder
        }
    }

    /// Neutral fill for a missing file URL (no leaking text).
    private var placeholder: some View {
        Color.black
            .ignoresSafeArea()
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(12)
                .background(.ultraThinMaterial, in: Circle())
        }
        .padding(.leading, 16)
        .padding(.top, 8)
        .accessibilityLabel("Close")
        .accessibilityIdentifier("viewerCloseButton")
    }
}
