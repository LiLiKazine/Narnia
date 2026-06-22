//
//  VaultGridView.swift
//  Narnia
//
//  The recursive vault grid: one screen per folder. The root (folderID == nil)
//  has no backing VaultItem; every deeper level is keyed by a folder's id.
//  Children are read LIVE via @Query so creating a folder (or any other write
//  through the shared ModelContext) reflects here without manual refresh.
//

import SwiftData
import SwiftUI

/// A grid of the children of a single folder. Folders navigate to a nested
/// `VaultGridView`; non-folder items are display-only in this slice.
struct VaultGridView: View {
    /// The folder whose children we show. `nil` == vault root.
    let folderID: UUID?
    /// Metadata CRUD. `@MainActor`, so it's safe to call directly from the view.
    let store: VaultStore
    /// Thumbnail generator/cache. An `actor` — always `await`-ed (in the cell).
    let thumbnails: ThumbnailService

    /// Live children of `folderID`, name-sorted by the query. Folders-first
    /// regrouping happens in `body` (a `SortDescriptor` can't express it).
    @Query private var items: [VaultItem]

    /// The current folder's own metadata, used only for the navigation title.
    /// Empty at the root (root has no backing VaultItem) — see `navigationTitle`.
    @Query private var selfItems: [VaultItem]

    /// Whether the New Folder alert is shown.
    @State private var isPresentingNewFolder = false
    /// Working text for the new folder's name. Reset to the default on present.
    @State private var newFolderName = ""

    /// Non-nil while the viewer is presented, carrying the item to open first.
    @State private var viewerPresentation: ViewerPresentation?

    /// Identifies which item the viewer should open at. `Identifiable` so it can
    /// drive `.fullScreenCover(item:)` without adding `Identifiable` to VaultItem.
    private struct ViewerPresentation: Identifiable {
        let id: UUID
    }

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 12)]

    init(folderID: UUID?, store: VaultStore, thumbnails: ThumbnailService) {
        self.folderID = folderID
        self.store = store
        self.thumbnails = thumbnails

        // Branch the predicate: a captured optional `UUID?` compared with `==`
        // does NOT compile to SQL `IS NULL`, so the root case must be its own
        // concrete predicate. (Same rule VaultStore.children(of:) follows.)
        let predicate: Predicate<VaultItem>
        if let folderID {
            predicate = #Predicate { $0.parentID == folderID }
        } else {
            predicate = #Predicate { $0.parentID == nil }
        }
        _items = Query(
            filter: predicate,
            sort: [SortDescriptor(\VaultItem.name, comparator: .localizedStandard)]
        )

        // Resolve the current folder's own name for the title. At the root there
        // is no VaultItem, so use a predicate that matches nothing (the query
        // stays empty and `navigationTitle` falls back to "Vault").
        let selfPredicate: Predicate<VaultItem>
        if let folderID {
            selfPredicate = #Predicate { $0.id == folderID }
        } else {
            selfPredicate = #Predicate { _ in false }
        }
        _selfItems = Query(filter: selfPredicate)
    }

    /// Folders first, then non-folders; within each group the query's localized
    /// name order is preserved (a stable sort keyed only on folder-ness).
    private var orderedItems: [VaultItem] {
        items.enumerated()
            .sorted { lhs, rhs in
                let lhsIsFolder = lhs.element.kind == .folder
                let rhsIsFolder = rhs.element.kind == .folder
                if lhsIsFolder != rhsIsFolder { return lhsIsFolder }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    /// The items the viewer pages across: this folder's non-folder items, in the
    /// same display order as the grid.
    private var viewableItems: [VaultItem] {
        orderedItems.filter { $0.kind != .folder }
    }

    var body: some View {
        Group {
            if items.isEmpty {
                emptyState
            } else {
                grid
            }
        }
        .navigationTitle(navigationTitle)
        .navigationDestination(for: UUID.self) { childID in
            VaultGridView(folderID: childID, store: store, thumbnails: thumbnails)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    newFolderName = "New Folder"
                    isPresentingNewFolder = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .accessibilityIdentifier("newFolderButton")
                .accessibilityLabel("New Folder")
            }
        }
        .alert("New Folder", isPresented: $isPresentingNewFolder) {
            TextField("Folder Name", text: $newFolderName)
                .accessibilityIdentifier("folderNameField")
            Button("Create") { createFolder() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a name for the new folder.")
        }
        .fullScreenCover(item: $viewerPresentation) { presentation in
            ViewerShell(items: viewableItems, startID: presentation.id, store: store)
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(orderedItems) { item in
                    cell(for: item)
                }
            }
            .padding(12)
        }
    }

    /// One grid entry. Folders are tappable navigation links; non-folders open
    /// the swipe-between-items viewer at the tapped item.
    @ViewBuilder
    private func cell(for item: VaultItem) -> some View {
        let cellView = VaultItemCell(
            item: item,
            fileURL: store.fileURL(for: item),
            thumbnails: thumbnails
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.name)

        // The accessibility identifier rides on the OUTER element so the UI test
        // can query it: a folder's NavigationLink surfaces as a button that
        // absorbs/collapses any identifier set on its inner content, so setting
        // it here keeps "item-<name>" resolvable for both folders and files.
        if item.kind == .folder {
            NavigationLink(value: item.id) {
                cellView
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("item-\(item.name)")
        } else {
            Button {
                presentViewer(startingAt: item)
            } label: {
                cellView
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("item-\(item.name)")
        }
    }

    private var emptyState: some View {
        Text("Empty")
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var navigationTitle: String {
        // The current folder isn't in `items` (those are its children); its own
        // metadata is in `selfItems`. Root has none → fall back to "Vault".
        selfItems.first?.name ?? "Vault"
    }

    /// Opens the viewer paging over `viewableItems`, starting at `item`.
    private func presentViewer(startingAt item: VaultItem) {
        viewerPresentation = ViewerPresentation(id: item.id)
    }

    private func createFolder() {
        let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? store.createFolder(name: trimmed, in: folderID)
    }
}
