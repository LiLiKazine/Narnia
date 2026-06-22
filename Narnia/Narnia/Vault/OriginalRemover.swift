import Foundation
import Photos

/// Best-effort removal of an imported file's original source. All methods are
/// best-effort: failures (no write scope, denied authorization) are swallowed.
///
/// Per spec §2 the import always copies into the vault first; removal of the
/// original is only ever attempted *after* that copy is confirmed. This protocol
/// is the seam the import path uses to perform that removal, so it can be
/// substituted in tests.
protocol OriginalRemoving: Sendable {
    /// Attempts to delete a file-system original (e.g. a document-picker URL).
    /// Read-only originals can't be deleted and will fail silently. The caller
    /// must still hold the security scope when this is called.
    func removeFileOriginal(at url: URL, securityScoped: Bool)

    /// Attempts to delete a Photos asset by its local identifier. iOS always
    /// shows its own deletion confirmation; denial or any error is swallowed.
    func removePhotoOriginal(localIdentifier: String) async
}

/// Concrete `OriginalRemoving` backed by `FileManager` and the Photos framework.
/// Stateless, hence trivially `Sendable`.
struct OriginalRemover: OriginalRemoving {
    func removeFileOriginal(at url: URL, securityScoped: Bool) {
        // Best-effort: the caller already holds the security scope. Read-only
        // originals (no write scope) will fail here — swallow it.
        try? FileManager.default.removeItem(at: url)
    }

    func removePhotoOriginal(localIdentifier: String) async {
        // Photos deletion needs read-write authorization. Request it if needed;
        // if the user declines, there's nothing to do.
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else { return }

        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard assets.count > 0 else { return }

        // iOS ALWAYS shows its own deletion confirmation here — expected.
        // Swallow all errors: removal is best-effort, the import already succeeded.
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets)
            }
        } catch {
            // Cancelled or failed — nothing to recover, the vault copy stands.
        }
    }
}
