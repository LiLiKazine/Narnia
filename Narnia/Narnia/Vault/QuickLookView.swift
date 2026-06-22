//
//  QuickLookView.swift
//  Narnia
//
//  QuickLook preview route for documents and unplanned file types — the
//  fallback viewer when an item isn't a photo or video (design spec §1).
//  Wraps QLPreviewController, which natively renders PDFs, Office/iWork docs,
//  text, and more.
//
//  Exfiltration note (spec §1): QuickLook ships its own share/print/open-in
//  affordances, which are an exfiltration path for vault contents. This view
//  restricts them as far as the public API allows; see `Coordinator` for the
//  measures taken and the documented residual limitation.
//

import QuickLook
import SwiftUI

/// Previews a single vault file using `QLPreviewController`.
///
/// One route inside the paging viewer shell. Editing/markup export is disabled.
/// The system share affordance cannot be fully removed via public API — see the
/// residual-limitation note on ``Coordinator``.
struct QuickLookView: View {
    private let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    var body: some View {
        PreviewControllerRepresentable(fileURL: fileURL)
            .background(Color.black)
            .ignoresSafeArea()
    }
}

/// Bridges `QLPreviewController` into SwiftUI.
///
/// QuickLook types are main-actor isolated, which `UIViewControllerRepresentable`
/// already guarantees for these methods. Nothing about the preview is dynamic
/// after creation, so `updateUIViewController` is intentionally a no-op.
private struct PreviewControllerRepresentable: UIViewControllerRepresentable {
    let fileURL: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(fileURL: fileURL)
    }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        // Nothing dynamic: the previewed file never changes for a given route.
    }
}

extension PreviewControllerRepresentable {
    /// Supplies the single preview item and clamps QuickLook's built-in actions.
    ///
    /// ## Exfiltration restrictions
    /// - `previewController(_:editingModeFor:)` returns `.disabled`, so QuickLook
    ///   offers no editing/markup mode — that closes the "edit, then export the
    ///   edited copy" path.
    ///
    /// ## Residual limitation (honest disclosure)
    /// `QLPreviewController` does **not** expose any public API to remove the
    /// share / Open-In affordance from its navigation bar. There is no supported
    /// switch (delegate hook, property, or otherwise) to suppress it, so this
    /// affordance remains reachable and is a real exfiltration surface. A fully
    /// locked-down preview would require replacing QuickLook with a custom
    /// per-type renderer (PDFKit, a text view, etc.) that exposes no share
    /// chrome — tracked as future work, not faked here.
    @MainActor
    final class Coordinator: NSObject, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
        private let fileURL: URL

        init(fileURL: URL) {
            self.fileURL = fileURL
        }

        // MARK: QLPreviewControllerDataSource

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(
            _ controller: QLPreviewController,
            previewItemAt index: Int
        ) -> any QLPreviewItem {
            fileURL as NSURL
        }

        // MARK: QLPreviewControllerDelegate

        /// Disable editing/markup so QuickLook cannot produce an exportable
        /// edited copy of the vault item.
        func previewController(
            _ controller: QLPreviewController,
            editingModeFor previewItem: any QLPreviewItem
        ) -> QLPreviewItemEditingMode {
            .disabled
        }
    }
}
