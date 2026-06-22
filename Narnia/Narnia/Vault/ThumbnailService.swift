//
//  ThumbnailService.swift
//  Narnia
//
//  Two-tier thumbnail cache for the vault grid. Photos are downsampled via
//  ImageIO; videos get a poster frame ~1s in via AVAssetImageGenerator.
//  Folders/documents/other never generate a thumbnail — the view layer draws
//  an SF Symbol for those.
//

import AVFoundation
import CoreGraphics
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// Generates and caches thumbnails for vault items, keyed by item `id`.
///
/// Only `.photo` and `.video` produce images; every other `ItemKind` returns
/// `nil` (no work, no cache entry). Lookup order is memory → disk → generate.
///
/// This is an `actor`: all parameters crossing its boundary are `Sendable`
/// primitives (`UUID`, `ItemKind`, `URL`, `CGFloat`). A `VaultItem` (which is
/// `@Model`/`@MainActor`) must never be passed in.
actor ThumbnailService {
    /// Directory holding the on-disk JPEG tier (`<id>.jpg`).
    private let thumbsDirectory: URL

    /// In-memory tier. `NSUUID` is the toll-free `NSObject` key for `UUID`.
    private let memoryCache = NSCache<NSUUID, UIImage>()

    /// JPEG quality for the on-disk tier. Thumbnails are small; 0.8 is plenty.
    private let diskJPEGQuality: CGFloat = 0.8

    init(thumbsDirectory: URL) {
        self.thumbsDirectory = thumbsDirectory
    }

    /// Returns a thumbnail for the given item, or `nil`.
    ///
    /// - `.folder`, `.document`, `.other` → always `nil` (no cache entry).
    /// - `.photo` → downsampled `fileURL` (nil if `fileURL` is nil/unreadable).
    /// - `.video` → poster frame ~1s in (nil on any failure).
    ///
    /// - Parameters:
    ///   - id: Stable identity used as the cache key.
    ///   - kind: Drives which generator (if any) runs.
    ///   - fileURL: Location of the source bytes; required for photo/video.
    ///   - maxPixel: Target max dimension (longest edge) in pixels.
    func thumbnail(for id: UUID,
                   kind: ItemKind,
                   fileURL: URL?,
                   maxPixel: CGFloat) async -> UIImage? {
        // Kinds that never have a thumbnail: bail before touching any cache.
        switch kind {
        case .folder, .document, .other:
            return nil
        case .photo, .video:
            break
        }

        let key = id as NSUUID

        // Tier 1: in-memory.
        if let cached = memoryCache.object(forKey: key) {
            return cached
        }

        // Tier 2: on-disk JPEG.
        let diskURL = diskURL(for: id)
        if let onDisk = loadFromDisk(at: diskURL) {
            memoryCache.setObject(onDisk, forKey: key)
            return onDisk
        }

        // Tier 3: generate.
        let generated: UIImage?
        switch kind {
        case .photo:
            generated = downsamplePhoto(at: fileURL, maxPixel: maxPixel)
        case .video:
            generated = await videoPoster(at: fileURL, maxPixel: maxPixel)
        case .folder, .document, .other:
            generated = nil // unreachable; handled above.
        }

        guard let image = generated else { return nil }

        // Populate both tiers.
        memoryCache.setObject(image, forKey: key)
        writeToDisk(image, at: diskURL)
        return image
    }

    // MARK: - Disk tier

    private func diskURL(for id: UUID) -> URL {
        thumbsDirectory.appendingPathComponent("\(id.uuidString).jpg", isDirectory: false)
    }

    private func loadFromDisk(at url: URL) -> UIImage? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    /// Writes the JPEG with complete file protection. Failures are swallowed —
    /// the in-memory tier still serves the image; the disk write is an
    /// optimization, not a correctness requirement.
    private func writeToDisk(_ image: UIImage, at url: URL) {
        guard let data = image.jpegData(compressionQuality: diskJPEGQuality) else { return }
        do {
            try FileManager.default.createDirectory(
                at: thumbsDirectory, withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
        } catch {
            // Best-effort cache; ignore.
        }
    }

    // MARK: - Photo generation (ImageIO downsample)

    private func downsamplePhoto(at fileURL: URL?, maxPixel: CGFloat) -> UIImage? {
        guard let fileURL else { return nil }

        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        guard let source = CGImageSourceCreateWithURL(
            fileURL as CFURL, sourceOptions as CFDictionary) else {
            return nil
        }

        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixel)
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
            source, 0, thumbOptions as CFDictionary) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }

    // MARK: - Video generation (AVAssetImageGenerator poster frame)

    private func videoPoster(at fileURL: URL?, maxPixel: CGFloat) async -> UIImage? {
        guard let fileURL else { return nil }

        let asset = AVURLAsset(url: fileURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: max(1, maxPixel), height: max(1, maxPixel))
        // Allow a wide tolerance so the generator can snap to the nearest
        // keyframe instead of failing on an exact match.
        generator.requestedTimeToleranceBefore = CMTime(seconds: 1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)

        // ~1s in; the tolerance above clamps gracefully for shorter clips.
        let time = CMTime(seconds: 1, preferredTimescale: 600)

        do {
            let (cgImage, _) = try await generator.image(at: time)
            return UIImage(cgImage: cgImage)
        } catch {
            return nil
        }
    }
}
