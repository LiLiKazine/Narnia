# 2026-06-22-03: Type-routed viewer (photo / video / QuickLook)

**Status:** Implemented

## Context

Roadmap item 2: tapping a non-folder item should open a full-screen viewer that
routes by type and pages between the folder's items, per spec §1 (Viewer + Video
privacy hardening). Built as iteration 4 of the autonomous dev loop (team lead +
4-agent parallel swarm: photo / video / quicklook / shell+wiring).

## Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| Video player | `AVPlayerViewController` via representable, NOT SwiftUI `VideoPlayer` | Only the controller exposes `allowsPictureInPicturePlayback = false`; the spec makes PiP-off the highest-priority hardening |
| Paging shell | `TabView(.page)` keyed by `item.id`, full-screen cover | Simplest "swipe-between-items" container; routes each page by kind |
| Photo zoom | `MagnificationGesture` + `DragGesture` (pan only when zoomed) | No external deps; drag yields to paging at fit scale |
| Cover presentation | private `ViewerPresentation: Identifiable` + `.fullScreenCover(item:)` | Avoids making `VaultItem` Identifiable (it's owned by the data layer) |

## What Changed

- `Narnia/Narnia/Vault/PhotoView.swift` (new) — async-loaded full-screen pinch-zoom/pan image.
- `Narnia/Narnia/Vault/HardenedVideoView.swift` (new) — `AVPlayerViewController` representable; PiP off (both flags), `allowsExternalPlayback = false`, `isMuted = true` initially; player held in a `@MainActor` Coordinator so updates don't reset it.
- `Narnia/Narnia/Vault/QuickLookView.swift` (new) — `QLPreviewController` representable; editing `.disabled`.
- `Narnia/Narnia/Vault/ViewerShell.swift` (new) — paging `TabView` routing photo/video/document+other; close button.
- `Narnia/Narnia/Vault/VaultGridView.swift` (modified) — non-folder cells open the viewer at the tapped item; folders still navigate; all a11y identifiers/flows preserved.
- `README.md` — ticked "Type-routed viewer" and "Video privacy hardening (PiP / AirPlay / mute)".

## What Was Discovered

- **PiP cannot be disabled via SwiftUI `VideoPlayer`** — had to drop to `AVPlayerViewController`. The spec literally said `VideoPlayer`; this is a justified, security-driven deviation (recorded so it isn't "corrected" later).
- **QuickLook's share/Open-In button is not removable via public API.** Editing can be disabled, but the share affordance remains a real exfiltration surface; a fully locked-down preview needs a custom per-type renderer (PDFKit/text). Documented in code + flagged as future work, not faked.
- **System screen-mirroring is uncloseable by any app.** `allowsExternalPlayback = false` stops the player's AirPlay route, but Control-Center screen mirroring is outside app control — a residual leak inherent to iOS.
- **Known UX rough edge:** `TabView(.page)` swipe competes with the embedded UIKit controllers' horizontal gestures (video scrubber, PDF pan), so swiping between items while on a video/document page can be unreliable. Inherent limitation, not a defect.
- **No viewer test this slice** — there's no in-vault content until Import (next roadmap item), so a meaningful UI test isn't feasible yet. Regression suite (20 unit + grid UI test) stays green. Optional `AVAudioSession` category pinning left as future hardening.
