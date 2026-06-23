# 2026-06-22-05: Import — originals removal + one-time preference (completes Import)

**Status:** Implemented — completes roadmap item "Import from Photos and Files".

## Context

The copy-in path landed in 2026-06-22-04. This slice adds the second half of spec
§2: a one-time best-effort "remove originals when possible" preference and actual
original deletion by source. Iteration 6 of the autonomous dev loop (team lead +
3-agent swarm: preference, ImportService+remover, grid wiring).

## Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| New ImportService params | additive with defaults (`removeOriginal = false`, `assetLocalIdentifier = nil`, injected `remover` with a default) | Existing call sites + classification tests keep compiling; change is purely additive |
| Deletion orchestration | inside `ImportService`, behind an injectable `OriginalRemoving` protocol | Keeps the delete-after-confirmed-copy ordering testable via a spy, no real Photos/Files needed |
| Preference storage | `OriginalsPreference` over `UserDefaults` (`ask`/`remove`/`keep`) | Spec wants it persisted + changeable later in Realm settings (separate item); UserDefaults is enough now |
| Photos asset id | `.photosPicker(..., photoLibrary: .shared())` so `itemIdentifier` is the asset localIdentifier | Required to delete the source PHAsset |
| `.limited` Photos auth | treated as sufficient to attempt deletion | The user already selected the asset; the OS confirmation gates it regardless |

## What Changed

- `OriginalsPreference.swift` (new) + tests — UserDefaults-backed disposition.
- `OriginalRemover.swift` (new) — `OriginalRemoving` protocol + concrete remover: best-effort `FileManager.removeItem` (read-only originals fail silently) and PHAsset deletion (requests read-write auth, swallows failures).
- `ImportService.swift` (modified) — injectable remover; `removeOriginal`/`assetLocalIdentifier` params; removal strictly AFTER a confirmed `storeFile`. `importData` is now `async`.
- `ImportServiceTests.swift` (modified) — `SpyRemover` + 4 tests, incl. the critical "copy fails → remover never called".
- `VaultGridView.swift` (modified) — photo-library-backed picker; one-time `confirmationDialog` prompt (Remove/Keep/Cancel) gating the first import; threads disposition into both import paths.
- `project.pbxproj` — `INFOPLIST_KEY_NSPhotoLibraryUsageDescription` on the app target (Debug+Release) for PHAsset deletion.
- `README.md` — ticked "Import from Photos and Files".

## What Was Discovered

- **Hard ordering verified end-to-end + test-locked** — removal sits after a `try store.storeFile(...)` in all three paths; a throwing copy never reaches the remover (proven by `importFileDoesNotRemoveOriginalWhenCopyFails`). For files, deletion runs inside the security-scoped access window.
- **Two-dialog reality on first Photos "remove"** — the in-app preference prompt is distinct from (and precedes) the OS deletion confirmation; both will show, as the spec anticipates.
- **Photos deletion is untestable in unit tests** — the spy proves the import path *calls* the remover with the right id and respects ordering; the real PHAsset behavior (auth + OS confirmation) is device/simulator-only. Matches the best-effort contract.
- **Prompt copy generalized** — review caught that the prompt fires for Files imports too, so the wording was changed from photo-specific to "file/original"; a Cancel was added that drops the stashed import and re-asks next time.
- **Simulator flake escalated** — the recurring `NarniaUITests.xctrunner` launch flake hit `testmanagerd` server-death twice in a row (no auto-retry). `xcrun simctl shutdown all` + re-run cleared it; unit-only runs were used to confirm the slice's logic in the meantime. Worth `simctl shutdown all` when the runner wedges.
- Deferred follow-ups (honest): surfacing import failures to the user; the Realm settings home for changing the originals toggle.
- **Follow-up fix — `nonisolated` on the remover is load-bearing** — the project sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so `OriginalRemoving`'s methods (and the `OriginalRemover` impl) defaulted to `@MainActor`. That made the `PHPhotoLibrary.performChanges` closure inherit `@MainActor` isolation, but Photos runs that block on its own private serial queue — tripping the runtime actor-isolation precondition. Marking both protocol requirements and impl methods `nonisolated` makes the change block default to nonisolated (correct: it does no UI work) and fixes the trap.
