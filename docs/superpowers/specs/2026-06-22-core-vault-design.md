# Core Vault — Engineering Design & Decisions

Status: **approved (team-lead decision, autonomous loop)** · 2026-06-22
Roadmap item: "Core vault: encrypted container, nested folders, grid" (README).
Authoritative product spec: `narnia-vault-design.md`. This doc records the
*engineering* decisions the spec deliberately left open. Do not contradict the
product spec; where it is silent, this doc governs.

## Decisions (locked)

1. **Encryption at rest = iOS Data Protection only.** Vault files are stored as
   plaintext in the app sandbox with `NSFileProtectionComplete`. No app-managed
   CryptoKit key, no per-file AES. Rationale: the spec's fresh-start-only session
   (§3) already reduces real-world protection to "device passcode + hidden door";
   an unlocked, handed-over phone is explicitly *not* defended against. Data
   Protection matches that posture (protects backups + a locked device) while
   removing key-management complexity. Recorded tradeoff: content is readable by
   anyone using the unlocked device — consistent with the accepted §3 tradeoff.

2. **Persistence = SwiftData (metadata) + files on disk.** A SwiftData store holds
   item metadata; file bytes live as files in the vault container, referenced by a
   relative path. Viewers read file URLs directly.

3. **Thumbnails = two-tier cache** (in-memory `NSCache` fronting an on-disk JPEG
   cache). Only photos and videos generate thumbnails; documents/other use static
   SF Symbols (no generation, no cache entry).

4. **Scope of this roadmap item, split across loop iterations:**
   - *Iteration 1 (this slice) — DATA LAYER:* `VaultItem` model, `VaultStore`
     (CRUD + file storage + recursive delete), `ThumbnailService`, unit tests.
   - *Iteration 2 — GRID UI:* recursive `VaultGridView`, cells, "New Folder".
   - **Deferred to later roadmap items:** file *import* UI (next roadmap item),
     move/rename, viewer.

5. **Build/test simulator = `iPhone 17`** (iPhone 16 is not installed on this
   machine; CLAUDE.md's example name is stale).

## Layout on disk

```
<app-container>/Library/Application Support/Vault/
    Narnia.store            ← SwiftData store (protected)
    files/<uuid>.<ext>      ← copied file bytes (NSFileProtectionComplete)
    thumbs/<uuid>.jpg       ← generated thumbnails (NSFileProtectionComplete)
```
The `Vault/` directory is the vault's sole root. Nothing here references cover or
closet data (spec isolation rule). Apply `NSFileProtectionComplete` to the `Vault`
directory and every file written under it.

## Source layout (Xcode synchronized groups — new files auto-included)

```
Narnia/Narnia/Vault/VaultItem.swift          (model-impl)
Narnia/Narnia/Vault/VaultStorage.swift       (store-impl)   paths + protection
Narnia/Narnia/Vault/VaultStore.swift         (store-impl)   SwiftData CRUD
Narnia/Narnia/Vault/ThumbnailService.swift   (thumbnail-impl)
Narnia/NarniaTests/VaultStoreTests.swift     (store-impl)
Narnia/NarniaTests/ThumbnailServiceTests.swift (thumbnail-impl)
```

## Contracts (agents MUST match these signatures exactly)

### VaultItem + ItemKind  (model-impl owns)

```swift
import Foundation
import SwiftData

enum ItemKind: String, Codable, CaseIterable, Sendable {
    case folder, photo, video, document, other
}

@Model
final class VaultItem {
    @Attribute(.unique) var id: UUID
    var parentID: UUID?          // nil == vault root
    var kind: ItemKind
    var name: String             // folder name, or filename for files
    var relativePath: String?    // nil for folders; "files/<uuid>.<ext>" for files
    var createdAt: Date

    init(id: UUID = UUID(), parentID: UUID?, kind: ItemKind,
         name: String, relativePath: String? = nil, createdAt: Date = Date()) {
        self.id = id; self.parentID = parentID; self.kind = kind
        self.name = name; self.relativePath = relativePath; self.createdAt = createdAt
    }
}
```

### VaultStorage  (store-impl owns) — filesystem + protection

```swift
@MainActor
struct VaultStorage {
    let root: URL                       // .../Vault
    var filesDir: URL { root.appending(path: "files") }
    var thumbsDir: URL { root.appending(path: "thumbs") }
    init() throws                       // creates dirs, applies NSFileProtectionComplete
    func url(forRelativePath path: String) -> URL
    /// Copy external bytes into files/<uuid>.<ext>; returns the relative path.
    /// Applies NSFileProtectionComplete to the written file.
    func storeFile(from source: URL, id: UUID) throws -> String
    func removeFile(relativePath: String) throws
    func removeThumb(id: UUID) throws
}
```

### VaultStore  (store-impl owns) — the API the grid will consume

```swift
@MainActor
final class VaultStore {
    init(context: ModelContext, storage: VaultStorage)
    func children(of parentID: UUID?) throws -> [VaultItem]   // sorted: folders first, then by name
    @discardableResult func createFolder(name: String, in parentID: UUID?) throws -> VaultItem
    @discardableResult func storeFile(from url: URL, kind: ItemKind, name: String, in parentID: UUID?) throws -> VaultItem
    /// Recursively deletes folders (descendants + their files + thumbs). Hard rule:
    /// metadata removed only after file bytes are removed.
    func delete(_ item: VaultItem) throws
    func fileURL(for item: VaultItem) -> URL?
}
```

### ThumbnailService  (thumbnail-impl owns)

```swift
import UIKit

actor ThumbnailService {
    init(thumbsDirectory: URL)
    /// Returns nil for .folder/.document/.other (caller uses an SF Symbol).
    /// Photo: downsample via ImageIO. Video: AVAssetImageGenerator poster ~1s in.
    /// Two-tier: NSCache(UUID->UIImage) over on-disk thumbs/<id>.jpg (protected).
    func thumbnail(for id: UUID, kind: ItemKind, fileURL: URL?, maxPixel: CGFloat) async -> UIImage?
}
```
Pass only `Sendable` values (UUID/ItemKind/URL) into the actor — never a `VaultItem`
(it is `@MainActor`/`@Model`). The view layer applies the video play badge.

## Concurrency

iOS 26.5 = Swift 6 strict concurrency. `VaultStore`/`VaultStorage` are `@MainActor`
(SwiftData `ModelContext` is main-actor bound). `ThumbnailService` is an `actor`.
No `VaultItem` crosses an actor boundary.

## Testing (Swift Testing — `import Testing`, `@Test`, `#expect`)

`VaultStoreTests`: build an in-memory `ModelContainer`
(`ModelConfiguration(isStoredInMemoryOnly: true)`) + a temp-dir `VaultStorage`.
Cover: createFolder + children nesting (parentID), storeFile copies bytes &
returns item with relativePath, recursive folder delete removes descendant
metadata AND their files/thumbs, children sort order (folders first).

`ThumbnailServiceTests`: generate a tiny PNG fixture in a temp dir; assert
thumbnail(.photo) is non-nil and a second call is served from cache; assert
thumbnail(.document) is nil. Video path tested only if a fixture can be made
cheaply (else assert nil-on-missing-URL doesn't crash). Do not leave failing tests.
