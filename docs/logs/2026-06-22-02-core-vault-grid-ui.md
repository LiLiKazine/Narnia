# 2026-06-22-02: Core Vault grid UI (recursive grid, cells, app wiring)

**Status:** Implemented

## Context

Second slice of the "Core vault" roadmap item, on top of the data layer
(`2026-06-22-01`). Needed the browsable UI: a recursive nested-folder grid, type
cells with thumbnails/captions, a way to create folders, and the app wired to
launch into the vault. Built as iteration 2 of the autonomous dev loop (main
agent = team lead, parallel implementation swarm).

## Options

| Decision | Choice | Why |
|----------|--------|-----|
| Reads | SwiftData `@Query` (dynamic predicate per `folderID`) for live updates | New folders/deletes refresh the grid automatically; writes still go through `VaultStore` on the same `mainContext` |
| Dependency injection | Explicit init injection of `store` + `thumbnails` down the recursive view | SwiftUI MV best practice; avoids a shared env-key file and the `@Entry` non-optional-default snag |
| Folders-first order | `@Query` name-sorts, view regroups folders-first in `body` | A `SortDescriptor` can't express enum-priority ordering |
| New Folder | Toolbar button → `.alert` with `TextField` | Rename is deferred, so naming at creation is the only path |
| Auth gate | None yet — app launches straight into the grid | Hidden-door auth is a later roadmap item |

## Decision

Recursive `VaultGridView(folderID:store:thumbnails:)` driven by `@Query`, with the
app constructing one `ModelContainer` at `Vault/Narnia.store`, a `VaultStore` on
its `mainContext`, and a `ThumbnailService` on `storage.thumbsDir`, all injected
from `NarniaApp` → `ContentView` → grid.

## What Changed

- `Narnia/Narnia/Vault/VaultGridView.swift` (new) — recursive `LazyVGrid`, live `@Query`, folders-first regroup, `navigationDestination(for: UUID.self)`, New Folder alert.
- `Narnia/Narnia/Vault/VaultItemCell.swift` (new) — async thumbnail via `.task(id:)`, SF-Symbol fallback by kind, video play badge, caption only for folder/document, uniform cell height.
- `Narnia/Narnia/NarniaApp.swift` (modified) — builds the shared container/store/thumbnails graph; co-locates the SwiftData store under the protected `Vault/`.
- `Narnia/Narnia/ContentView.swift` (modified) — `NavigationStack { VaultGridView(folderID: nil, …) }` + an in-memory preview.
- `Narnia/NarniaUITests/VaultGridUITests.swift` (new) — XCUITest: create folder → assert it appears.
- `README.md` — ticked "Core vault: encrypted container, nested folders, grid".

## What Was Discovered

- **a11y identifiers collapse under `NavigationLink` + `.combine`.** An identifier on
  the inner cell content was absorbed by the folder's `NavigationLink` (rendered as a
  button), so `app.descendants[...]` couldn't find it. Fix: put the identifier on the
  outer element and query `app.buttons[...]`.
- **iOS 26 drops `.accessibilityIdentifier` on a `TextField` inside `.alert`.** The UI
  test had to locate the field via the alert hierarchy (`app.alerts[...].textFields.firstMatch`)
  rather than by identifier.
- **Folders-first ordering now lives in two places** (`VaultStore.ordering` and the
  view regroup). Left as-is this slice — they take different input shapes (the view
  relies on the query's name sort) and forcing a shared comparator risked drift;
  flagged as a future cleanup.
- The `#Preview`'s `let …; return SomeView()` triggers a SourceKit warning but compiles
  fine (`@ViewBuilder` tolerates it here). SourceKit also reports spurious
  same-module "cannot find type" errors — xcodebuild is authoritative.
