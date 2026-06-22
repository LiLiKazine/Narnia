//
//  VaultGridView.swift
//  Narnia
//
//  The recursive vault grid: one screen per folder. The root (folderID == nil)
//  has no backing VaultItem; every deeper level is keyed by a folder's id.
//  Children are read LIVE via @Query so creating a folder (or any other write
//  through the shared ModelContext) reflects here without manual refresh.
//

import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

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

    /// Whether the Photos picker is shown (triggered from the Import menu).
    @State private var showPhotosPicker = false
    /// Whether the Files importer is shown (triggered from the Import menu).
    @State private var showFileImporter = false
    /// Selection from the Photos picker; drained and imported on change.
    @State private var photoSelection: [PhotosPickerItem] = []

    /// The user's saved "remove originals when possible" choice. Asked once, on
    /// the first import from any source, then honored silently thereafter.
    @State private var originalsPreference = OriginalsPreference()
    /// Whether the one-time "remove originals?" prompt is shown.
    @State private var isPresentingOriginalsPrompt = false
    /// The import waiting on the user's answer to the one-time prompt. Stashed
    /// when the prompt is raised, then run with the chosen disposition.
    @State private var pendingImport: PendingImport?

    /// An import deferred until the one-time originals prompt is answered.
    private enum PendingImport {
        case photos([PhotosPickerItem])
        case files([URL])
    }

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
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Import from Photos") { showPhotosPicker = true }
                    Button("Import from Files") { showFileImporter = true }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("importButton")
                .accessibilityLabel("Import")
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
        .photosPicker(
            isPresented: $showPhotosPicker,
            selection: $photoSelection,
            maxSelectionCount: 0,
            matching: .any(of: [.images, .videos]),
            photoLibrary: .shared()
        )
        .onChange(of: photoSelection) { _, newSelection in
            beginImport(.photos(newSelection))
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            guard case let .success(urls) = result else { return }
            beginImport(.files(urls))
        }
        .confirmationDialog(
            "Remove originals when possible?",
            isPresented: $isPresentingOriginalsPrompt,
            titleVisibility: .visible
        ) {
            Button("Remove Originals") {
                originalsPreference.disposition = .remove
                runPendingImport()
            }
            .accessibilityIdentifier("removeOriginalsButton")
            Button("Keep Originals") {
                originalsPreference.disposition = .keep
                runPendingImport()
            }
            .accessibilityIdentifier("keepOriginalsButton")
            Button("Cancel", role: .cancel) {
                // Dismissed without choosing: drop the stashed import and leave the
                // preference at .ask so the next import asks again.
                pendingImport = nil
            }
        } message: {
            Text(
                "When you import a file, Narnia can remove the original from its "
                    + "source when possible. You'll still confirm any Photos deletion."
            )
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

    /// Entry point for any import. On the very first import (from either source)
    /// the user hasn't chosen a disposition yet, so we stash the work and raise
    /// the one-time prompt; the prompt's actions resume via `runPendingImport`.
    /// Once answered, later imports run immediately with the saved choice.
    private func beginImport(_ pending: PendingImport) {
        guard hasContent(pending) else { return }
        if originalsPreference.hasBeenAsked {
            perform(pending)
        } else {
            pendingImport = pending
            isPresentingOriginalsPrompt = true
        }
    }

    /// Runs the import stashed when the one-time prompt was raised, using the
    /// disposition the user just chose. Clears the stash afterward.
    private func runPendingImport() {
        guard let pending = pendingImport else { return }
        pendingImport = nil
        perform(pending)
    }

    private func hasContent(_ pending: PendingImport) -> Bool {
        switch pending {
        case let .photos(items): return !items.isEmpty
        case let .files(urls): return !urls.isEmpty
        }
    }

    private func perform(_ pending: PendingImport) {
        switch pending {
        case let .photos(items): importPhotos(items)
        case let .files(urls): importFiles(urls)
        }
    }

    /// Copies each picked photo/video into the current folder via ImportService.
    /// `loadTransferable` and `importData` are async, so the work runs in a Task;
    /// the service is `@MainActor` (as is this view), so its calls stay on the
    /// main actor. Each item's `itemIdentifier` is the asset's localIdentifier
    /// (the picker uses `.shared()`), passed through so the importer can remove
    /// the original when the user opted in. The selection is drained afterward
    /// so re-picking the same asset re-fires.
    private func importPhotos(_ selection: [PhotosPickerItem]) {
        guard !selection.isEmpty else { return }
        let removeOriginal = originalsPreference.shouldRemove
        Task {
            let importer = ImportService(store: store)
            for item in selection {
                let data = try? await item.loadTransferable(type: Data.self)
                guard let data else { continue }
                let contentType = item.supportedContentTypes.first
                let suggestedName = "Photo-\(UUID().uuidString.prefix(8))"
                try? await importer.importData(
                    data,
                    suggestedName: suggestedName,
                    contentType: contentType,
                    assetLocalIdentifier: item.itemIdentifier,
                    into: folderID,
                    removeOriginal: removeOriginal
                )
            }
            photoSelection = []
        }
    }

    /// Copies each picked file into the current folder via ImportService.
    /// The service handles security-scoped access. Failures (including the
    /// importer's own `.failure`) are swallowed — no error UI leaks.
    private func importFiles(_ urls: [URL]) {
        let removeOriginal = originalsPreference.shouldRemove
        let importer = ImportService(store: store)
        for url in urls {
            try? importer.importFile(
                at: url,
                into: folderID,
                securityScoped: true,
                removeOriginal: removeOriginal
            )
        }
    }
}
