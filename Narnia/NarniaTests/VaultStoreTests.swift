//
//  VaultStoreTests.swift
//  NarniaTests
//
//  Unit tests for the vault storage + persistence layer.
//

import Foundation
import Testing
import SwiftData
@testable import Narnia

// `.serialized` + a single shared `ModelContainer`: standing up a *new*
// in-memory `ModelContainer(for: VaultItem.self)` per test traps inside the
// SwiftData runtime once several have been created in the same process — every
// test then crashes at its first `context.save()` (folders-first, files later),
// taking the whole test process down. The fix is to build the container exactly
// once (`Self.sharedContainer`) and give each test a fresh, wiped context from
// it. Wiping + serial execution keeps tests isolated despite the shared store.
@MainActor
@Suite(.serialized)
struct VaultStoreTests {

    // MARK: - Fixture

    /// One in-memory SwiftData container for the whole suite. Created lazily on
    /// first use; reused by every test (see the note above for why per-test
    /// containers crash).
    private static let sharedContainer: ModelContainer = {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: VaultItem.self, configurations: config)
    }()

    /// An in-memory SwiftData stack plus a temp-dir `VaultStorage`. The temp
    /// directory is removed by `cleanup()`.
    private struct Fixture {
        let store: VaultStore
        let storage: VaultStorage
        let tempRoot: URL

        func cleanup() {
            try? FileManager.default.removeItem(at: tempRoot)
        }
    }

    private func makeFixture() throws -> Fixture {
        // Fresh context off the shared container, wiped clean so each test sees
        // an empty vault. Safe because the suite runs serialized.
        let context = ModelContext(Self.sharedContainer)
        try context.delete(model: VaultItem.self)
        try context.save()

        let tempRoot = FileManager.default.temporaryDirectory
            .appending(path: "VaultStoreTests-\(UUID().uuidString)")
        let storage = try VaultStorage(root: tempRoot)
        let store = VaultStore(context: context, storage: storage)
        return Fixture(store: store, storage: storage, tempRoot: tempRoot)
    }

    /// Writes a small file into a temp location and returns its URL.
    private func makeSourceFile(ext: String, contents: String = "hello vault") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "src-\(UUID().uuidString).\(ext)")
        try Data(contents.utf8).write(to: url)
        return url
    }

    // MARK: - createFolder / children nesting

    @Test func createFolderAppearsInChildren() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let folder = try fixture.store.createFolder(name: "Docs", in: nil)
        let rootChildren = try fixture.store.children(of: nil)

        #expect(rootChildren.count == 1)
        #expect(rootChildren.first?.id == folder.id)
        #expect(rootChildren.first?.name == "Docs")
        #expect(rootChildren.first?.kind == .folder)
    }

    @Test func nestedFolderResolvesByParentID() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let parent = try fixture.store.createFolder(name: "Parent", in: nil)
        let child = try fixture.store.createFolder(name: "Child", in: parent.id)

        // Child shows under its parent, not at the root.
        let rootChildren = try fixture.store.children(of: nil)
        #expect(rootChildren.count == 1)
        #expect(rootChildren.first?.id == parent.id)

        let parentChildren = try fixture.store.children(of: parent.id)
        #expect(parentChildren.count == 1)
        #expect(parentChildren.first?.id == child.id)
        #expect(parentChildren.first?.parentID == parent.id)
    }

    // MARK: - storeFile copies bytes

    @Test func storeFileCopiesBytesAndReturnsResolvableItem() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let source = try makeSourceFile(ext: "txt", contents: "secret contents")
        defer { try? FileManager.default.removeItem(at: source) }

        let item = try fixture.store.storeFile(
            from: source, kind: .document, name: "note.txt", in: nil
        )

        // Metadata is correct.
        #expect(item.kind == .document)
        #expect(item.name == "note.txt")
        let relativePath = try #require(item.relativePath)
        #expect(relativePath == "files/\(item.id.uuidString).txt")

        // Bytes exist on disk and match the source.
        let onDisk = fixture.storage.url(forRelativePath: relativePath)
        #expect(FileManager.default.fileExists(atPath: onDisk.path))
        let copied = try Data(contentsOf: onDisk)
        #expect(copied == Data("secret contents".utf8))

        // fileURL(for:) points at the existing bytes.
        let resolved = try #require(fixture.store.fileURL(for: item))
        #expect(resolved == onDisk)
        #expect(FileManager.default.fileExists(atPath: resolved.path))
    }

    @Test func fileURLIsNilForFolders() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let folder = try fixture.store.createFolder(name: "Folder", in: nil)
        #expect(fixture.store.fileURL(for: folder) == nil)
    }

    @Test func storeFileWithoutExtensionOmitsDot() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        // Source with no extension.
        let source = FileManager.default.temporaryDirectory
            .appending(path: "noext-\(UUID().uuidString)")
        try Data("x".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }

        let item = try fixture.store.storeFile(
            from: source, kind: .other, name: "blob", in: nil
        )
        #expect(item.relativePath == "files/\(item.id.uuidString)")
    }

    // MARK: - recursive delete

    @Test func recursiveDeleteRemovesAllDescendantsAndBytes() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        // Tree: root/Folder -> { Subfolder, file.txt }, Subfolder -> { deep.txt }
        let folder = try fixture.store.createFolder(name: "Folder", in: nil)
        let subfolder = try fixture.store.createFolder(name: "Subfolder", in: folder.id)

        let src1 = try makeSourceFile(ext: "txt", contents: "top")
        defer { try? FileManager.default.removeItem(at: src1) }
        let topFile = try fixture.store.storeFile(
            from: src1, kind: .document, name: "file.txt", in: folder.id
        )

        let src2 = try makeSourceFile(ext: "txt", contents: "deep")
        defer { try? FileManager.default.removeItem(at: src2) }
        let deepFile = try fixture.store.storeFile(
            from: src2, kind: .document, name: "deep.txt", in: subfolder.id
        )

        // Plant a thumbnail for one of the files to confirm it is removed too.
        let thumbURL = fixture.storage.thumbsDir
            .appending(path: "\(deepFile.id.uuidString).jpg")
        try Data("thumb".utf8).write(to: thumbURL)
        #expect(FileManager.default.fileExists(atPath: thumbURL.path))

        let topBytes = try #require(fixture.store.fileURL(for: topFile))
        let deepBytes = try #require(fixture.store.fileURL(for: deepFile))
        #expect(FileManager.default.fileExists(atPath: topBytes.path))
        #expect(FileManager.default.fileExists(atPath: deepBytes.path))

        // Delete the top folder recursively.
        try fixture.store.delete(folder)

        // All metadata gone.
        #expect(try fixture.store.children(of: nil).isEmpty)
        #expect(try fixture.store.children(of: folder.id).isEmpty)
        #expect(try fixture.store.children(of: subfolder.id).isEmpty)

        // All bytes + thumbnail gone from disk.
        #expect(!FileManager.default.fileExists(atPath: topBytes.path))
        #expect(!FileManager.default.fileExists(atPath: deepBytes.path))
        #expect(!FileManager.default.fileExists(atPath: thumbURL.path))
    }

    @Test func deleteSingleFileRemovesBytes() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let source = try makeSourceFile(ext: "txt")
        defer { try? FileManager.default.removeItem(at: source) }
        let item = try fixture.store.storeFile(
            from: source, kind: .document, name: "a.txt", in: nil
        )
        let bytes = try #require(fixture.store.fileURL(for: item))
        #expect(FileManager.default.fileExists(atPath: bytes.path))

        try fixture.store.delete(item)

        #expect(try fixture.store.children(of: nil).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: bytes.path))
    }

    // MARK: - sort order

    @Test func childrenSortFoldersFirstThenCaseInsensitiveName() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        // Insert in a deliberately scrambled order.
        _ = try fixture.store.createFolder(name: "banana", in: nil)
        _ = try fixture.store.createFolder(name: "Apple", in: nil)

        let srcZ = try makeSourceFile(ext: "txt")
        defer { try? FileManager.default.removeItem(at: srcZ) }
        _ = try fixture.store.storeFile(from: srcZ, kind: .document, name: "zebra.txt", in: nil)

        let srcA = try makeSourceFile(ext: "txt")
        defer { try? FileManager.default.removeItem(at: srcA) }
        _ = try fixture.store.storeFile(from: srcA, kind: .document, name: "Avocado.txt", in: nil)

        let names = try fixture.store.children(of: nil).map(\.name)
        // Folders first (case-insensitive: Apple < banana), then files
        // (Avocado.txt < zebra.txt).
        #expect(names == ["Apple", "banana", "Avocado.txt", "zebra.txt"])
    }
}
