import Foundation

/// Filesystem layout + iOS Data Protection for the vault container.
///
/// Owns the on-disk side of the vault: the `Vault/` root, its `files/` and
/// `thumbs/` subdirectories, and the copying/removal of file bytes. Every
/// directory and file written here is marked `NSFileProtectionComplete`, which
/// is the vault's sole encryption-at-rest mechanism (see core-vault-design).
///
/// `@MainActor` to compose cleanly with `VaultStore`, which is main-actor bound
/// by SwiftData. The work here is plain filesystem I/O.
@MainActor
struct VaultStorage {
    /// The vault's sole root directory (`.../Library/Application Support/Vault`).
    let root: URL

    /// Where copied file bytes live: `root/files/<uuid>.<ext>`.
    var filesDir: URL { root.appending(path: "files") }

    /// Where generated thumbnails live: `root/thumbs/<uuid>.jpg`.
    var thumbsDir: URL { root.appending(path: "thumbs") }

    /// Default root under Application Support. Creates the directory tree and
    /// applies `NSFileProtectionComplete` to every level.
    init() throws {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        try self.init(root: appSupport.appending(path: "Vault"))
    }

    /// Explicit-root initializer (used by tests with a temp directory). Creates
    /// the directory tree and applies `NSFileProtectionComplete` to every level.
    init(root: URL) throws {
        self.root = root
        try createProtectedDirectory(at: root)
        try createProtectedDirectory(at: filesDir)
        try createProtectedDirectory(at: thumbsDir)
    }

    /// Resolves a stored relative path (e.g. `"files/<uuid>.<ext>"`) against the
    /// vault root.
    func url(forRelativePath path: String) -> URL {
        root.appending(path: path)
    }

    /// Copies external bytes into `files/<uuid>.<ext>`, applies
    /// `NSFileProtectionComplete` to the written file, and returns the relative
    /// path (`"files/<uuid>.<ext>"`, or `"files/<uuid>"` when the source has no
    /// extension).
    ///
    /// The copy happens before any caller records metadata; if it throws, no
    /// dangling metadata should be created.
    func storeFile(from source: URL, id: UUID) throws -> String {
        let ext = source.pathExtension
        let filename = ext.isEmpty ? id.uuidString : "\(id.uuidString).\(ext)"
        let relativePath = "files/\(filename)"
        let destination = url(forRelativePath: relativePath)

        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.copyItem(at: source, to: destination)
        try applyProtection(to: destination)
        return relativePath
    }

    /// Removes the file bytes at `relativePath`. No-op if already absent.
    func removeFile(relativePath: String) throws {
        let url = url(forRelativePath: relativePath)
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
    }

    /// Removes `thumbs/<id>.jpg` if present. No error if the thumbnail was never
    /// generated.
    func removeThumb(id: UUID) throws {
        let url = thumbsDir.appending(path: "\(id.uuidString).jpg")
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
    }
}

// MARK: - Protection helpers

private func createProtectedDirectory(at url: URL) throws {
    let fm = FileManager.default
    try fm.createDirectory(
        at: url,
        withIntermediateDirectories: true,
        attributes: [.protectionKey: FileProtectionType.complete]
    )
    try applyProtection(to: url)
}

private func applyProtection(to url: URL) throws {
    try FileManager.default.setAttributes(
        [.protectionKey: FileProtectionType.complete],
        ofItemAtPath: url.path
    )
}
