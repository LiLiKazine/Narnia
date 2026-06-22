# 2026-06-22-08: Realm settings screen + shared originals preference

**Status:** Implemented — roadmap item "Realm settings screen" (originals toggle wired; security toggles deferred to their own items).

## Context

Spec §5: a settings screen "summoned by the originals preference", whose first
inhabitant is the "remove originals when possible" toggle, and the future home for
security toggles. Until now `OriginalsPreference` was constructed ad hoc per import
in `VaultGridView` — settings would need to share that state. Iteration 9 of the
autonomous dev loop (team lead + 2-agent swarm).

## Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| Shared state | ONE `OriginalsPreference`, owned by ContentView `@State`, injected into VaultGridView (threaded through recursion) + SettingsView | Single source of truth between the import prompt and the settings control |
| Observability | made `OriginalsPreference` `@MainActor @Observable` (stored `disposition` + `didSet` persistence) | Lets the Picker bind via `@Bindable` and the import path see changes; keeps the same UserDefaults key/default |
| Control | a 3-case `Picker` (Ask each time / Remove when possible / Keep originals) | Surfaces the full disposition clearly; "Ask each time" lets the user reset to the first-import prompt |
| Entry point | a gear toolbar button in the vault grid → `.sheet(SettingsView)` | Lives inside the unlocked vault, never on the cover — preserves the disguise |
| Future toggles | empty "Security" section stub (Hide-names, flip-to-lock) | Those are separate roadmap items; structure them in, don't build |

## What Changed

- `OriginalsPreference.swift` — `@Observable`; `disposition` is now a stored property (init reads UserDefaults; `didSet` persists). API/key/default unchanged; enum gained `CaseIterable`.
- `SettingsView.swift` (new) — `@Bindable` Form: "Imports" section with the originals Picker (+ best-effort caption), an empty "Security" section stub, Done button.
- `ContentView.swift` — owns the single `@State OriginalsPreference`, injects it into the root `VaultGridView`.
- `VaultGridView.swift` — `init` now takes `originalsPreference`; removed the ad-hoc `@State` instance; gear button → settings sheet; threads the shared preference into recursive children + the import prompt.
- `OriginalsPreferenceTests.swift` — kept persistence tests under the @Observable impl; added an unrecognized-value→.ask case.
- `VaultGridUITests.swift` — `testSettingsOpensAndShowsOriginalsControl`.
- `README.md` — ticked Realm settings.

## What Was Discovered

- **@Observable + UserDefaults** needs a *stored* property (not computed-over-UserDefaults) for observation to fire; a `didSet` bridges persistence, and Swift's "no `didSet` during init" rule means load doesn't redundantly write.
- **Reference-type sharing made the refactor clean** — `OriginalsPreference` is a class, so threading one instance through the recursive grid + the sheet + the import path gives genuine single-source state with no syncing.
- **`.ask` is intentionally user-selectable** — picking "Ask each time" sets `hasBeenAsked` false again, so the next import re-prompts. A deliberate "reset" affordance, not an accident.
- **Sim flake reminder:** running `xcrun simctl shutdown all` immediately before a test run can itself wedge the runner (`Current state: Shutdown`). Better to re-run plainly and only shut down when the runner is actually stuck. Unit tests passed throughout; a clean re-run went fully green.
- Deferred (honest): the Hide-names toggle and flip-face-down-to-lock now have a home here but are their own roadmap items.
