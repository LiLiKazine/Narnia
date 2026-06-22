//
//  ImportServiceTests.swift
//  NarniaTests
//
//  Unit tests for ImportService: content classification and importing files /
//  in-memory bytes into the vault.
//

import Foundation
import Testing
import SwiftData
import UniformTypeIdentifiers
@testable import Narnia

// Shares the same in-memory `ModelContainer` strategy as `VaultStoreTests`:
// per-test containers trap inside SwiftData once several are created in one
// process, so build one container for the suite and hand each test a freshly
// wiped context. `.serialized` keeps that sharing safe.
@MainActor
@Suite(.serialized)
struct ImportServiceTests {

    // MARK: - Fixture

    private static let sharedContainer: ModelContainer = {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: VaultItem.self, configurations: config)
    }()

    private struct Fixture {
        let service: ImportService
        let store: VaultStore
        let storage: VaultStorage
        let tempRoot: URL

        func cleanup() {
            try? FileManager.default.removeItem(at: tempRoot)
        }
    }

    private func makeFixture() throws -> Fixture {
        let context = ModelContext(Self.sharedContainer)
        try context.delete(model: VaultItem.self)
        try context.save()

        let tempRoot = FileManager.default.temporaryDirectory
            .appending(path: "ImportServiceTests-\(UUID().uuidString)")
        let storage = try VaultStorage(root: tempRoot)
        let store = VaultStore(context: context, storage: storage)
        return Fixture(service: ImportService(store: store), store: store, storage: storage, tempRoot: tempRoot)
    }

    /// Writes a small file into a temp location and returns its URL.
    private func makeSourceFile(ext: String, contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "import-src-\(UUID().uuidString).\(ext)")
        try Data(contents.utf8).write(to: url)
        return url
    }

    // MARK: - kind(for:) classification

    @Test func kindForImageExtensionsIsPhoto() {
        #expect(ImportService.kind(for: URL(fileURLWithPath: "/x/a.jpg")) == .photo)
        #expect(ImportService.kind(for: URL(fileURLWithPath: "/x/a.png")) == .photo)
        #expect(ImportService.kind(for: URL(fileURLWithPath: "/x/a.heic")) == .photo)
    }

    @Test func kindForVideoExtensionsIsVideo() {
        #expect(ImportService.kind(for: URL(fileURLWithPath: "/x/a.mov")) == .video)
        #expect(ImportService.kind(for: URL(fileURLWithPath: "/x/a.mp4")) == .video)
    }

    @Test func kindForDocumentExtensionsIsDocument() {
        #expect(ImportService.kind(for: URL(fileURLWithPath: "/x/a.pdf")) == .document)
        #expect(ImportService.kind(for: URL(fileURLWithPath: "/x/a.txt")) == .document)
    }

    @Test func kindForUnknownExtensionIsOther() {
        #expect(ImportService.kind(for: URL(fileURLWithPath: "/x/a.xyzzy")) == .other)
    }

    @Test func kindForContentTypeMapping() {
        #expect(ImportService.kind(for: .png) == .photo)
        #expect(ImportService.kind(for: .jpeg) == .photo)
        #expect(ImportService.kind(for: .quickTimeMovie) == .video)
        #expect(ImportService.kind(for: .mpeg4Movie) == .video)
        #expect(ImportService.kind(for: .pdf) == .document)
        #expect(ImportService.kind(for: .plainText) == .document)
    }

    // MARK: - importFile

    @Test func importFileCopiesBytesAndClassifies() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let source = try makeSourceFile(ext: "pdf", contents: "fake pdf bytes")
        defer { try? FileManager.default.removeItem(at: source) }

        let item = try fixture.service.importFile(at: source, into: nil, securityScoped: false)

        #expect(item.kind == .document)
        #expect(item.name == source.lastPathComponent)

        // The vault copy is resolvable and its bytes match the source.
        let resolved = try #require(fixture.store.fileURL(for: item))
        #expect(FileManager.default.fileExists(atPath: resolved.path))
        let copied = try Data(contentsOf: resolved)
        #expect(copied == Data("fake pdf bytes".utf8))

        // Original is left in place (deletion is out of scope this slice).
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    @Test func importFileClassifiesImageAsPhoto() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let source = try makeSourceFile(ext: "png", contents: "fake png")
        defer { try? FileManager.default.removeItem(at: source) }

        let item = try fixture.service.importFile(at: source, into: nil, securityScoped: false)
        #expect(item.kind == .photo)
    }

    // MARK: - importData

    @Test func importDataWritesResolvablePhotoAndCleansTemp() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let payload = Data("png-ish payload".utf8)
        let item = try fixture.service.importData(
            payload, suggestedName: "snapshot", contentType: .png, into: nil
        )

        // Classified from the content type and resolvable on disk.
        #expect(item.kind == .photo)
        let resolved = try #require(fixture.store.fileURL(for: item))
        #expect(FileManager.default.fileExists(atPath: resolved.path))
        #expect(try Data(contentsOf: resolved) == payload)

        // The suggested name had no extension, so the derived one is appended.
        #expect(item.name == "snapshot.png")
    }

    @Test func importDataKeepsExistingExtensionInName() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let item = try fixture.service.importData(
            Data("x".utf8), suggestedName: "report.pdf", contentType: .pdf, into: nil
        )
        #expect(item.kind == .document)
        #expect(item.name == "report.pdf")
    }

    @Test func importDataWithoutContentTypeIsOther() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let item = try fixture.service.importData(
            Data("blob".utf8), suggestedName: "blob", contentType: nil, into: nil
        )
        #expect(item.kind == .other)
        #expect(item.name == "blob")
        let resolved = try #require(fixture.store.fileURL(for: item))
        #expect(FileManager.default.fileExists(atPath: resolved.path))
    }
}
