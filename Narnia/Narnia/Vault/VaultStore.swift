import Foundation
import SwiftData

/// SwiftData-backed CRUD for the vault: folders and files as `VaultItem`
/// metadata, with file bytes managed by `VaultStorage`.
///
/// `@MainActor` because SwiftData's `ModelContext` is main-actor bound. The
/// store enforces the spec's hard ordering rule: file bytes (and any thumbnail)
/// are removed from disk *before* the corresponding metadata is deleted, so a
/// crash mid-delete can never leave metadata pointing at vanished bytes — only
/// (harmless) orphaned bytes with no metadata.
@MainActor
final class VaultStore {
    private let context: ModelContext
    private let storage: VaultStorage

    init(context: ModelContext, storage: VaultStorage) {
        self.context = context
        self.storage = storage
    }

    /// Direct children of `parentID` (pass `nil` for the vault root), sorted
    /// folders-first, then case-insensitively by name.
    func children(of parentID: UUID?) throws -> [VaultItem] {
        // Branch the fetch: comparing a captured optional `UUID?` with `==` in a
        // `#Predicate` mis-handles the root case at runtime (it does not compile
        // to SQL `IS NULL`). Build a concrete predicate per case instead.
        let descriptor: FetchDescriptor<VaultItem>
        if let parentID {
            descriptor = FetchDescriptor(predicate: #Predicate { $0.parentID == parentID })
        } else {
            descriptor = FetchDescriptor(predicate: #Predicate { $0.parentID == nil })
        }
        let items = try context.fetch(descriptor)
        return items.sorted(by: Self.ordering)
    }

    /// Creates a folder under `parentID` and returns its metadata.
    @discardableResult
    func createFolder(name: String, in parentID: UUID?) throws -> VaultItem {
        let folder = VaultItem(parentID: parentID, kind: .folder, name: name)
        context.insert(folder)
        try context.save()
        return folder
    }

    /// Copies bytes from `url` into the vault, then records the file's metadata.
    ///
    /// The copy happens first; if it throws, no metadata is inserted. The stored
    /// `name` is the logical filename, independent of the on-disk `<uuid>.<ext>`.
    @discardableResult
    func storeFile(from url: URL, kind: ItemKind, name: String, in parentID: UUID?) throws -> VaultItem {
        let id = UUID()
        // Bytes first — if this throws we never reach the metadata insert.
        let relativePath = try storage.storeFile(from: url, id: id)

        let item = VaultItem(
            id: id,
            parentID: parentID,
            kind: kind,
            name: name,
            relativePath: relativePath
        )
        do {
            context.insert(item)
            try context.save()
        } catch {
            // Roll back the orphaned bytes so a failed save leaves nothing behind.
            try? storage.removeFile(relativePath: relativePath)
            try? storage.removeThumb(id: id)
            throw error
        }
        return item
    }

    /// Deletes `item`. For folders, recursively deletes every descendant
    /// (folders and files). For each file, the bytes and thumbnail are removed
    /// from disk *before* the metadata, per the hard ordering rule.
    func delete(_ item: VaultItem) throws {
        try deleteRecursively(item)
        try context.save()
    }

    /// Resolves the on-disk URL for a file item. `nil` for folders or any item
    /// without a `relativePath`.
    func fileURL(for item: VaultItem) -> URL? {
        guard let relativePath = item.relativePath else { return nil }
        return storage.url(forRelativePath: relativePath)
    }

    // MARK: - Private

    /// Deletes an item and all descendants, removing bytes before metadata.
    /// Does not save — the caller saves once after the whole subtree is removed.
    private func deleteRecursively(_ item: VaultItem) throws {
        if item.kind == .folder {
            for child in try children(of: item.id) {
                try deleteRecursively(child)
            }
        }
        // Bytes + thumbnail first, then metadata. Order is the invariant.
        if let relativePath = item.relativePath {
            try storage.removeFile(relativePath: relativePath)
        }
        try storage.removeThumb(id: item.id)
        context.delete(item)
    }

    /// Folders before files; within a group, case-insensitive name order.
    private static func ordering(_ lhs: VaultItem, _ rhs: VaultItem) -> Bool {
        let lhsIsFolder = lhs.kind == .folder
        let rhsIsFolder = rhs.kind == .folder
        if lhsIsFolder != rhsIsFolder {
            return lhsIsFolder
        }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
}
