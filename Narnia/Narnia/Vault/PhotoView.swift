//
//  PhotoView.swift
//  Narnia
//
//  Full-screen photo viewer: one route inside the paging viewer shell. Loads a
//  vault-owned image off the main thread, then presents it black-backgrounded
//  edge to edge with pinch-to-zoom, pan-when-zoomed, and double-tap to toggle
//  between fit and a closer view. No filenames or error text are shown — a photo
//  is self-explanatory, and a load failure falls back to a neutral glyph so
//  nothing about the file leaks.
//

import SwiftUI

/// Displays the image at `fileURL` full-screen with interactive zoom and pan.
///
/// The bytes are read asynchronously in a `.task`; a `ProgressView` covers the
/// gap and a `photo` SF Symbol stands in if decoding fails. Gestures are kept
/// deliberately simple — no external dependencies — and operate purely on local
/// view state, so this view references no other vault data.
struct PhotoView: View {
    /// On-disk location of the decrypted image bytes for this photo.
    let fileURL: URL

    @State private var image: UIImage?
    @State private var loadFailed = false

    /// Committed zoom scale (updated when a pinch ends).
    @State private var scale: CGFloat = 1
    /// Live scale during an in-progress pinch, multiplied onto `scale`.
    @State private var gestureScale: CGFloat = 1
    /// Committed pan offset (updated when a drag ends).
    @State private var offset: CGSize = .zero
    /// Live pan translation during an in-progress drag.
    @State private var dragOffset: CGSize = .zero

    private let minScale: CGFloat = 1
    private let maxScale: CGFloat = 6
    /// Target magnification for a double-tap zoom-in.
    private let doubleTapScale: CGFloat = 2

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    var body: some View {
        ZStack {
            Color.black

            if let image {
                imageContent(image)
            } else if loadFailed {
                placeholder
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .ignoresSafeArea()
        .task(id: fileURL) {
            await load()
        }
    }

    // MARK: - Content

    private func imageContent(_ image: UIImage) -> some View {
        // Effective transform = committed value combined with any live gesture.
        let effectiveScale = scale * gestureScale
        let effectiveOffset = CGSize(
            width: offset.width + dragOffset.width,
            height: offset.height + dragOffset.height
        )

        return Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .scaleEffect(effectiveScale)
            .offset(effectiveOffset)
            .gesture(magnification)
            .simultaneousGesture(pan(isZoomed: effectiveScale > 1))
            .onTapGesture(count: 2) { toggleZoom() }
            .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.8), value: scale)
            .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.8), value: offset)
    }

    private var placeholder: some View {
        Image(systemName: "photo")
            .font(.system(size: 48))
            .foregroundStyle(.secondary)
    }

    // MARK: - Gestures

    private var magnification: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                gestureScale = value
            }
            .onEnded { _ in
                let resolved = min(max(scale * gestureScale, minScale), maxScale)
                scale = resolved
                gestureScale = 1
                if resolved == minScale {
                    offset = .zero
                }
            }
    }

    private func pan(isZoomed: Bool) -> some Gesture {
        DragGesture()
            .onChanged { value in
                // Only pan while zoomed in; at fit scale a drag does nothing,
                // leaving room for the shell's paging swipe to take over.
                guard isZoomed else { return }
                dragOffset = value.translation
            }
            .onEnded { value in
                guard isZoomed else { return }
                offset = CGSize(
                    width: offset.width + value.translation.width,
                    height: offset.height + value.translation.height
                )
                dragOffset = .zero
            }
    }

    private func toggleZoom() {
        if scale > minScale {
            scale = minScale
            offset = .zero
        } else {
            scale = doubleTapScale
        }
        gestureScale = 1
        dragOffset = .zero
    }

    // MARK: - Loading

    private func load() async {
        // Read and decode off the main actor. UIImage is safe to construct on a
        // background task and hand back to this @MainActor view after decode.
        let url = fileURL
        let decoded = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return UIImage(data: data)
        }.value

        if let decoded {
            image = decoded
        } else {
            loadFailed = true
        }
    }
}
