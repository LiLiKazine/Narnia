//
//  ThumbnailServiceTests.swift
//  NarniaTests
//
//  Covers the two-tier cache (memory → disk → generate) and the kinds that
//  never produce a thumbnail.
//

import Foundation
import Testing
import UIKit

@testable import Narnia

struct ThumbnailServiceTests {

    // MARK: - Helpers

    /// Creates a fresh, unique temp directory and returns its URL.
    private func makeTempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ThumbTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func removeDir(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Writes a tiny solid-color PNG and returns its URL.
    private func writeTinyPNG(in dir: URL) throws -> URL {
        let size = CGSize(width: 4, height: 4)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            UIColor.systemTeal.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        let data = try #require(image.pngData())
        let url = dir.appendingPathComponent("fixture-\(UUID().uuidString).png")
        try data.write(to: url)
        return url
    }

    // MARK: - Photo path

    @Test func photoThumbnailIsGeneratedAndCachedToDisk() async throws {
        let workDir = makeTempDir()
        defer { removeDir(workDir) }

        let thumbsDir = workDir.appendingPathComponent("thumbs", isDirectory: true)
        let service = ThumbnailService(thumbsDirectory: thumbsDir)
        let photoURL = try writeTinyPNG(in: workDir)
        let id = UUID()

        // First call generates.
        let first = await service.thumbnail(
            for: id, kind: .photo, fileURL: photoURL, maxPixel: 64)
        #expect(first != nil)

        // The on-disk JPEG tier should now exist.
        let diskURL = thumbsDir.appendingPathComponent("\(id.uuidString).jpg")
        #expect(FileManager.default.fileExists(atPath: diskURL.path))

        // Second call (same id) is still served and non-nil.
        let second = await service.thumbnail(
            for: id, kind: .photo, fileURL: photoURL, maxPixel: 64)
        #expect(second != nil)
    }

    @Test func diskTierServesAfterMemoryIsBypassed() async throws {
        let workDir = makeTempDir()
        defer { removeDir(workDir) }

        let thumbsDir = workDir.appendingPathComponent("thumbs", isDirectory: true)
        let photoURL = try writeTinyPNG(in: workDir)
        let id = UUID()

        // Populate disk via one service instance.
        let first = await ThumbnailService(thumbsDirectory: thumbsDir)
            .thumbnail(for: id, kind: .photo, fileURL: photoURL, maxPixel: 64)
        #expect(first != nil)

        // A brand-new instance has an empty memory cache; it must load from
        // disk even if the source file is gone.
        try FileManager.default.removeItem(at: photoURL)
        let fromDisk = await ThumbnailService(thumbsDirectory: thumbsDir)
            .thumbnail(for: id, kind: .photo, fileURL: photoURL, maxPixel: 64)
        #expect(fromDisk != nil)
    }

    @Test func photoWithNilURLReturnsNil() async {
        let workDir = makeTempDir()
        defer { removeDir(workDir) }

        let service = ThumbnailService(
            thumbsDirectory: workDir.appendingPathComponent("thumbs"))
        let result = await service.thumbnail(
            for: UUID(), kind: .photo, fileURL: nil, maxPixel: 64)
        #expect(result == nil)
    }

    @Test func photoWithUnreadableURLReturnsNil() async {
        let workDir = makeTempDir()
        defer { removeDir(workDir) }

        let service = ThumbnailService(
            thumbsDirectory: workDir.appendingPathComponent("thumbs"))
        let bogus = workDir.appendingPathComponent("does-not-exist.png")
        let result = await service.thumbnail(
            for: UUID(), kind: .photo, fileURL: bogus, maxPixel: 64)
        #expect(result == nil)
    }

    // MARK: - Non-thumbnail kinds

    @Test func documentReturnsNilAndWritesNothing() async {
        let workDir = makeTempDir()
        defer { removeDir(workDir) }

        let thumbsDir = workDir.appendingPathComponent("thumbs", isDirectory: true)
        let service = ThumbnailService(thumbsDirectory: thumbsDir)
        let id = UUID()

        let result = await service.thumbnail(
            for: id, kind: .document, fileURL: nil, maxPixel: 64)
        #expect(result == nil)

        let diskURL = thumbsDir.appendingPathComponent("\(id.uuidString).jpg")
        #expect(FileManager.default.fileExists(atPath: diskURL.path) == false)
    }

    @Test func folderAndOtherReturnNil() async {
        let workDir = makeTempDir()
        defer { removeDir(workDir) }

        let service = ThumbnailService(
            thumbsDirectory: workDir.appendingPathComponent("thumbs"))

        let folder = await service.thumbnail(
            for: UUID(), kind: .folder, fileURL: nil, maxPixel: 64)
        #expect(folder == nil)

        let other = await service.thumbnail(
            for: UUID(), kind: .other, fileURL: nil, maxPixel: 64)
        #expect(other == nil)
    }

    // MARK: - Video path (negative only — no cheap fixture)

    @Test func videoWithNilURLReturnsNilWithoutCrashing() async {
        let workDir = makeTempDir()
        defer { removeDir(workDir) }

        let service = ThumbnailService(
            thumbsDirectory: workDir.appendingPathComponent("thumbs"))
        let result = await service.thumbnail(
            for: UUID(), kind: .video, fileURL: nil, maxPixel: 64)
        #expect(result == nil)
    }

    @Test func videoWithGarbageURLReturnsNilWithoutCrashing() async {
        let workDir = makeTempDir()
        defer { removeDir(workDir) }

        let service = ThumbnailService(
            thumbsDirectory: workDir.appendingPathComponent("thumbs"))
        // A non-video file masquerading as a URL: generator should fail cleanly.
        let garbage = workDir.appendingPathComponent("not-a-video.mov")
        try? Data([0x00, 0x01, 0x02, 0x03]).write(to: garbage)

        let result = await service.thumbnail(
            for: UUID(), kind: .video, fileURL: garbage, maxPixel: 64)
        #expect(result == nil)
    }
}
