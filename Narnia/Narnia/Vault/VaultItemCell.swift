//
//  VaultItemCell.swift
//  Narnia
//
//  A single grid cell: a square thumbnail (or type icon while it loads / when
//  none exists), an optional video play badge, and an optional caption. Per the
//  design spec, only folders and documents get a caption — photos and videos
//  are self-explanatory and show none. Cell heights stay uniform regardless so
//  grid rows align: the caption area is always reserved.
//

import SwiftUI

/// Renders one `VaultItem` as a square tile. Thumbnails are fetched lazily from
/// the `ThumbnailService`; until one arrives (or for kinds that never have one)
/// a kind-appropriate SF Symbol stands in.
struct VaultItemCell: View {
    let item: VaultItem
    /// On-disk location of the item's bytes, or `nil` (folders, missing files).
    let fileURL: URL?
    let thumbnails: ThumbnailService
    /// Target longest-edge size for the generated thumbnail, in pixels.
    let maxPixel: CGFloat

    @State private var image: UIImage?

    init(item: VaultItem, fileURL: URL?, thumbnails: ThumbnailService, maxPixel: CGFloat = 300) {
        self.item = item
        self.fileURL = fileURL
        self.thumbnails = thumbnails
        self.maxPixel = maxPixel
    }

    var body: some View {
        VStack(spacing: 6) {
            thumbnailSquare
            caption
        }
        .task(id: item.id) {
            image = await thumbnails.thumbnail(
                for: item.id,
                kind: item.kind,
                fileURL: fileURL,
                maxPixel: maxPixel
            )
        }
    }

    private var thumbnailSquare: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color(.secondarySystemBackground))
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: symbolName)
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if item.kind == .video {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                        .padding(6)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// Caption row. Only `.folder` and `.document` show text; other kinds get an
    /// empty placeholder of the same height so every cell is the same size.
    @ViewBuilder
    private var caption: some View {
        Group {
            if showsCaption {
                Text(item.name)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.primary)
            } else {
                // Reserve the line so rows with/without captions align.
                Text(" ")
                    .font(.caption)
                    .lineLimit(1)
                    .hidden()
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var showsCaption: Bool {
        item.kind == .folder || item.kind == .document
    }

    private var symbolName: String {
        switch item.kind {
        case .folder: "folder.fill"
        case .photo: "photo"
        case .video: "film"
        case .document: "doc.fill"
        case .other: "doc"
        }
    }
}
