# 2026-06-22-01: Core Vault data layer (model, storage, store, thumbnails)

**Status:** Implemented

## Context

First implementation slice of the "Core vault" roadmap item. Needed the
foundational, type-agnostic data layer the grid/viewer/import will all build on:
a persistence model for nested folders + files, an on-disk storage layout for
file bytes, CRUD with correct deletion semantics, and thumbnail generation. The
product spec (`narnia-vault-design.md`) deliberately left the engineering choices
open; this slice locks them. Done as iteration 1 of an autonomous dev loop with
the main agent as team lead dispatching an implementation swarm.

## Options

### Encryption at rest

| Approach | Pros | Cons |
|----------|------|------|
| App-managed CryptoKit (AES-GCM, Keychain key) | Defends an unlocked/handed-over phone + backups | Key lifecycle complexity; contradicts the already-accepted fresh-start session posture |
| Hybrid CryptoKit + Data Protection | Strongest | Most setup |
| iOS Data Protection only (chosen) | No key management; protects backups + locked device | Readable on an *unlocked* device |

### Persistence

| Approach | Pros | Cons |
|----------|------|------|
| SwiftData metadata + files on disk (chosen) | SwiftUI-native (@Query), light DB, viewers read file URLs directly | Newer framework |
| Pure filesystem model | Single source of truth | Metadata/ordering/thumbnail-caching awkward |
| Core Data + files | Mature | Boilerplate, less SwiftUI-native |

### Thumbnails

| Approach | Pros | Cons |
|----------|------|------|
| Two-tier NSCache + on-disk (chosen) | Survives cold launch, avoids re-extracting video posters | Slightly more code |
| On-disk only | Simple | More disk I/O while scrolling |
| In-memory only | Simplest | Re-extracts everything each cold launch |

## Decision

iOS Data Protection (`NSFileProtectionComplete`) at rest; SwiftData for metadata
with file bytes stored as plaintext files on disk; two-tier (NSCache over on-disk
JPEG) thumbnail cache for photos/videos only.

## Rationale

Data Protection is consistent with the spec's fresh-start-only session (§3),
which already reduces real-world protection to "device passcode + hidden door" —
an unlocked handed-over phone is explicitly out of scope. So app-managed crypto
would add key-management complexity without changing the threat posture. SwiftData
is the native iOS 26.5 + SwiftUI fit. Thumbnails are the spec's stated "real work",
so the persistent two-tier cache is justified up front.

## What Changed

- `docs/superpowers/specs/2026-06-22-core-vault-design.md` — engineering design + locked decisions + exact contracts.
- `Narnia/Narnia/Vault/VaultItem.swift` — `@Model VaultItem` (polymorphic: folders are items) + `ItemKind` enum.
- `Narnia/Narnia/Vault/VaultStorage.swift` — `@MainActor` filesystem layer: `Vault/{files,thumbs}`, `NSFileProtectionComplete`, copy/remove primitives.
- `Narnia/Narnia/Vault/VaultStore.swift` — `@MainActor` SwiftData CRUD: `children(of:)`, `createFolder`, `storeFile`, recursive `delete`, `fileURL(for:)`.
- `Narnia/Narnia/Vault/ThumbnailService.swift` — `actor`; ImageIO downsample (photo) + AVAssetImageGenerator poster (video); two-tier cache; nil for folder/document/other.
- `Narnia/NarniaTests/{VaultStoreTests,ThumbnailServiceTests}.swift` — Swift Testing unit tests.

Deferred to later slices: grid UI, file import, move/rename, viewer.

## What Was Discovered

- **SwiftData traps on per-test in-memory containers.** The test harness originally
  built a fresh `ModelContainer(isStoredInMemoryOnly: true)` per test; after a few
  in one process the SwiftData runtime hits an `EXC_BREAKPOINT` during `save()`,
  crashing the whole runner — which surfaced as *every* `VaultStoreTests` failing
  instantly (0.000s), masking the real cause. Fix: one suite-wide shared container,
  a fresh wiped `ModelContext` per test, and `@Suite(.serialized)`.
- **`#Predicate` with a captured optional is fragile.** `#Predicate { $0.parentID == parentID }`
  for a `UUID?` does not yield SQL `IS NULL` for the root case. Branch the
  `FetchDescriptor`: literal `$0.parentID == nil` for root, `== parentID` otherwise.
- **Delete ordering holds via byte-before-metadata.** Recursive folder delete removes
  each descendant's bytes + thumb before its SwiftData object; a single `save()` after
  the subtree means a mid-delete crash can only orphan bytes (harmless), never strand
  metadata pointing at missing bytes.
- **Follow-up (next slices):** project is still `SWIFT_VERSION = 5.0` (not Swift 6
  strict-concurrency mode) though the code is written strict-clean — flip it on as a
  focused slice. `iPhone 16` from CLAUDE.md isn't installed; builds use `iPhone 17`.
