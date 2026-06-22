# 2026-06-22-04: Import — copy-in path (Photos + Files)

**Status:** Implemented (partial — first sub-slice of roadmap item "Import from Photos and Files")

## Context

Roadmap item 3, spec §2. The vault could only hold folders created in-app; there
was no way to get real content in. This slice adds importing photos/videos (Photos
picker) and arbitrary files (document picker) into the current folder. Iteration 5
of the autonomous dev loop (team lead + 2-agent swarm). Original-deletion and the
one-time "remove originals" preference are deliberately deferred to a later slice.

## Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| Pickers | SwiftUI `.photosPicker` + `.fileImporter` | Both permission-free & out-of-process; no Info.plist usage strings → preserves the spec's "disguise pays no cost". (Spec names PHPickerViewController; the SwiftUI photosPicker is the same PHPicker under the hood.) |
| Import "+" | Separate toolbar Menu, New Folder button left intact | Avoids regressing the `newFolderButton` UI test |
| Copy path | Reuse `VaultStore.storeFile` (copy-before-insert) | Honors the hard ordering rule for free; one write path into the Data-Protection container |
| Originals deletion | DEFERRED | Photos deletion needs a PHAsset change request (triggers the OS confirmation) + the preference prompt; belongs with the Realm settings slice |

## What Changed

- `Narnia/Narnia/Vault/ImportService.swift` (new) — `@MainActor`; `kind(for:)` UTType→ItemKind classification (image→photo, movie/video→video, content→document, else other); `importFile(at:into:securityScoped:)` (brackets start/stopAccessingSecurityScopedResource, copy inside the window); `importData(_:suggestedName:contentType:into:)` (temp file → storeFile → defer cleanup).
- `Narnia/NarniaTests/ImportServiceTests.swift` (new) — classification + import-copy unit tests.
- `Narnia/Narnia/Vault/VaultGridView.swift` (modified) — Import menu ("+") with Photos/Files; `.photosPicker`/`.fileImporter` handlers calling ImportService into the current folder. New Folder, viewer, @Query, a11y identifiers untouched.

## What Was Discovered

- **No permissions/Info.plist needed** — both pickers are out-of-process; confirmed no `NS*UsageDescription` exists or was added. The disguise stays cost-free for import (matches spec §2).
- **Originals deletion is genuinely a separate concern** — it needs photo-library access (which the import itself does not) and always surfaces the OS deletion confirmation, plus the preference prompt. Correctly deferred rather than half-built.
- **Two reviewers independently flagged a dead `documentTypes` array** in `kind(for:)` (every entry already conforms to `.content`) — simplified to the single `.content` check (behavior-identical, re-verified by tests).
- **Recurring CI flake:** the `NarniaUITests.xctrunner` occasionally fails to launch on one simulator clone (`FBSOpenApplicationServiceErrorDomain`), but xcodebuild retries on another clone and the suite ends `TEST SUCCEEDED`. Cosmetic/simulator-level, not a code issue — noting so it isn't mistaken for a real failure.
- **No viewer/import UI test yet** — exercising the system Photos/Files pickers from XCUITest is brittle; the ImportService unit tests cover the core copy + classification logic instead.
- Deferred follow-ups: originals-removal preference + deletion; surfacing import failures to the user (currently swallowed by design).
