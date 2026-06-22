import Foundation
import UniformTypeIdentifiers

/// Copies external files and in-memory bytes into the vault.
///
/// A thin policy layer over `VaultStore`: it classifies incoming content into an
/// `ItemKind`, manages security-scoped access and temp files for the two import
/// sources (the document picker and `PhotosPicker`), and delegates the actual
/// copy-then-record to `VaultStore.storeFile`. Per spec §2 this slice copies
/// originals into the vault container only — it never deletes the originals.
///
/// `@MainActor` because every call funnels into the main-actor-bound
/// `VaultStore`.
@MainActor
struct ImportService {
    let store: VaultStore

    init(store: VaultStore) {
        self.store = store
    }

    // MARK: - Classification

    /// Maps a content type to a vault `ItemKind`. Order matters: image and
    /// movie/audiovisual checks come before the broad `.content` fallback, since
    /// most concrete document types also conform to `.content`.
    static func kind(for contentType: UTType) -> ItemKind {
        if contentType.conforms(to: .image) {
            return .photo
        }
        if contentType.conforms(to: .movie)
            || contentType.conforms(to: .video)
            || contentType.conforms(to: .audiovisualContent) {
            return .video
        }
        // Concrete document types (PDF, text, RTF, spreadsheet, …) all conform to
        // `.content`, so this single check covers them once image/video are ruled out.
        if contentType.conforms(to: .content) {
            return .document
        }
        return .other
    }

    /// Maps a file URL to a vault `ItemKind` by resolving its path extension to a
    /// `UTType`. Returns `.other` when the extension maps to no known type.
    static func kind(for url: URL) -> ItemKind {
        guard let contentType = UTType(filenameExtension: url.pathExtension) else {
            return .other
        }
        return kind(for: contentType)
    }

    // MARK: - Import

    /// Imports a file from a (possibly security-scoped) URL into `parentID`.
    ///
    /// When `securityScoped` is true — as for URLs returned by the system
    /// document picker — access is bracketed with
    /// `start`/`stopAccessingSecurityScopedResource`. The copy itself is handled
    /// by `VaultStore.storeFile`, which copies bytes before recording metadata.
    @discardableResult
    func importFile(at source: URL, into parentID: UUID?, securityScoped: Bool) throws -> VaultItem {
        if securityScoped {
            guard source.startAccessingSecurityScopedResource() else {
                throw ImportError.accessDenied
            }
            defer { source.stopAccessingSecurityScopedResource() }
            return try store.storeFile(
                from: source,
                kind: Self.kind(for: source),
                name: source.lastPathComponent,
                in: parentID
            )
        }
        return try store.storeFile(
            from: source,
            kind: Self.kind(for: source),
            name: source.lastPathComponent,
            in: parentID
        )
    }

    /// Imports in-memory bytes (e.g. from `PhotosPicker`) into `parentID`.
    ///
    /// Writes the data to a temp file carrying the content type's preferred
    /// extension (so `VaultStore` stores it as `<uuid>.<ext>`), imports it, and
    /// always removes the temp file afterward. The recorded `name` is
    /// `suggestedName`, with the derived extension appended only when the
    /// suggested name lacks one of its own.
    @discardableResult
    func importData(
        _ data: Data,
        suggestedName: String,
        contentType: UTType?,
        into parentID: UUID?
    ) throws -> VaultItem {
        let ext = contentType?.preferredFilenameExtension
        let tempName = ext.map { "\(UUID().uuidString).\($0)" } ?? UUID().uuidString
        let tempURL = FileManager.default.temporaryDirectory.appending(path: tempName)
        try data.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let name = resolvedName(suggestedName, ext: ext)
        let kind = contentType.map(Self.kind(for:)) ?? .other
        return try store.storeFile(from: tempURL, kind: kind, name: name, in: parentID)
    }

    // MARK: - Private

    /// Returns `suggestedName` unchanged if it already has an extension;
    /// otherwise appends the derived extension when one is available.
    private func resolvedName(_ suggestedName: String, ext: String?) -> String {
        guard (suggestedName as NSString).pathExtension.isEmpty, let ext else {
            return suggestedName
        }
        return "\(suggestedName).\(ext)"
    }
}

/// Errors surfaced by `ImportService`.
enum ImportError: Error {
    /// A security-scoped URL could not be accessed for reading.
    case accessDenied
}
