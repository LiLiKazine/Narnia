# Narnia — Vault Design Spec

The design of the realm: the private store hidden behind the back of the wardrobe. This document captures the decisions made for the vault itself, and complements the earlier `narnia-product-design.md` (whole-product), `narnia-roadmap.md` (engineering layers), and `narnia-product-cycle.md` (PM process).

## Identity note

The vault began as a *media vault* (photos + HD video). During design it expanded to hold documents and arbitrary file types, which makes it a **private file vault** — closer to an encrypted Files.app than to Photos. The storage and folder layers are type-agnostic (a file is a file), so this expansion changed only the two ends: how items are displayed and how they're opened. The shift also reinforced the file-system/nested model chosen for organization.

---

## 1. Browse & Display

**Grid.** A unified, system-styled `LazyVGrid` in a `ScrollView`. No custom theming for v1 — it looks like a tidy, ordinary media app, with light/dark following the system. Mood and restraint are a later polish pass. The lazy grid handles memory for large stores; the real engineering work is thumbnail generation and caching from the vault's own files, not the layout.

**Folders.** Nested directories (a true file-system model, not flat-with-albums). Each item has a single `parentFolderID`. One recursive view renders every level: it shows sub-folders and loose media together; tapping a folder pushes the same view for the child folder, tapping media opens the viewer. This is less code than separate screens and matches the file-manager mental model.

**Item types.** Polymorphic — photo, video, document, and a catch-all "other." Folders also appear in the grid as items.

**Thumbnails, by type:**
- Photo — the image itself.
- Video — a poster frame extracted with `AVAssetImageGenerator` (~1s in), cached like a photo thumbnail. Badged with a play glyph.
- Document — a **generic type icon** (SF Symbols: `doc.fill`, `doc.text`, etc.), not a rendered page. This is instant, uniform, requires no thumbnail cache, and — importantly — avoids putting actual document content into the grid where it could be read at a glance.
- Other / unknown — a catch-all type icon.

**Captions.** Self-explanatory items (photo, video) show no caption. Items that need identifying (documents, folders) show a caption: filename or folder name. Cell heights are kept consistent so rows align whether or not a caption is present. Consequence formally accepted: documents make on-screen text unavoidable, so a "wordless" vault is off the table. Because document thumbnails are generic icons, the **caption is the sole identifier** for a document and is load-bearing.

**Viewer.** A router by item type:
- Photo → full-screen pinch-zoom image view.
- Video → `AVPlayer` via SwiftUI `VideoPlayer`.
- Everything else → **QuickLook** (`QLPreviewController`), which previews PDFs, Office/iWork docs, text, and more natively, and acts as the fallback for unplanned file types.

A common swipe-between-items shell wraps all three. Note QuickLook offers its own share/print/open-in actions — these are an exfiltration path and should be restricted.

**Video privacy hardening** (video leaks in ways photos can't):
- Picture-in-Picture **off** — otherwise vault video keeps playing in a floating window over other apps after you leave. Highest-priority item.
- AirPlay / external display **off** — prevents a stray tap throwing video to a nearby TV.
- Audio **starts muted**, user unmutes deliberately — a tap in a quiet room shouldn't blast sound.

---

## 2. Import

**Sources (v1):** two.
- Photos → `PHPickerViewController`. Runs out-of-process, returns only selected items, and requires **no photo-library permission prompt** — the disguise pays no cost.
- Files / docs / other → `.fileImporter` (document picker). Also out-of-process, no permission, returns security-scoped URLs.

Import targets the current folder (respects the nested model). The "＋" lives in the grid.

**Originals preference.** Whether to remove an original after import is governed by a single best-effort preference, surfaced as a **one-time in-app prompt at the first import**, then saved (and changeable later in realm settings). Wording: "remove originals *when possible*" — it is not a guarantee.

Behavior by source:
- Photos original — the app can *attempt* removal, but iOS **always** shows its own deletion confirmation (verified: this holds even with Full Photo Library Access; the prompt is tied to the delete operation, not the authorization level). On the very first Photos import with "remove" chosen, the user sees two dialogs back-to-back — the one-time preference prompt, then the OS confirmation. Only stacks once.
- Document-picker original — removable only if write scope was granted; read-only originals can't be deleted at all.
- Vault-owned copies — fully under app control, deleted silently via `FileManager`, no prompt ever.

**Hard ordering rule:** only attempt to delete an original *after* the vault copy is confirmed written to disk. Never the reverse — a failed copy plus a successful delete loses the file.

**Deferred / optional:**
- Camera-direct-into-vault — the cleanest privacy story (no original ever exists outside the vault), at the cost of a capture UI inside the realm. Optional stretch.
- Share extension (import from Safari/Mail/etc.) — deferred: a separate app target sharing the encryption key across an app group, plus a disguise cost.

---

## 3. Security & Session Model

**Entry.** One way in, always: long-press the wooden back-panel at the end of the Outerwear tab, confirmed by Face ID / Touch ID. No button, no password field, no "unlock" label anywhere.

**Session — "fresh start only."** Authentication happens **once per app lifetime**. After crossing the threshold you remain in the vault until the process is actually terminated. Backgrounding, app-switching, checking a notification, the screen auto-locking — none of these eject you or re-prompt; returning to the app lands you back exactly where you were. The vault re-locks only on a **cold launch**.

Explicitly decided *against*:
- Ejecting to the cover on background.
- Face-ID-on-return / silent re-verification.
- App-switcher snapshot cover — the multitasking thumbnail shows whatever's on screen, vault content included.

**Footnote (not a bug).** A "fresh start" is not fully under the user's control: iOS reclaims backgrounded apps under memory pressure, which terminates the process and invalidates the session. This produces occasional involuntary re-auths even when the user never swiped the app away.

### Noted design tradeoff (deliberate, not an oversight)

The fresh-start-only model was chosen knowingly. Its cost: because the session survives backgrounding, anyone who reopens the app while it's still in memory — most concretely, **a person you hand your unlocked phone to** — lands directly inside the vault, with the hidden door and biometric never re-firing. In effect this reduces the vault's protection to the device passcode, which the people one typically hides content from (partner, children) often already know. The recommended alternative was *Face ID on foreground-return* (keep your place, re-verify silently in ~0.5s, fall through to the cover on failure), which preserves low friction while restoring the protection. This was discussed and the fresh-start-only model was chosen anyway. Recorded here so the tradeoff is visible to future decisions.

---

## 4. Cross-cutting storage notes

- Vault files are copied into the app's own (encrypted) container, kept in a store entirely separate from the cover/closet data — the two should never reference each other.
- Silent, full control over vault-owned files; the only OS-mandated confirmation anywhere is removing an *original* from the Photos library.

---

## 5. Open items (not yet designed)

- **Quick-exit / panic.** Unresolved, and made *more* relevant by the session choice: since backgrounding no longer ejects to the cover, swiping home is no longer a clean panic (returning lands back in the vault). An explicit in-app exit (thumb-reachable, collapses all folder depth at once, stops any playing video) and/or an opt-in flip-face-down-to-lock were discussed but not settled.
- **Realm settings screen.** Summoned by the originals preference but not yet designed; currently its only confirmed inhabitant is the "remove originals when possible" toggle. Future home for any security toggles too.
- **"Hide names" toggle.** Possible mitigation for the on-screen-text leak introduced by captions; not yet specced.

---

## Engineering touchpoints (APIs referenced)

`LazyVGrid` · `AVAssetImageGenerator` · `VideoPlayer` / `AVPlayer` · `QLPreviewController` · `PHPickerViewController` · `.fileImporter` · `LocalAuthentication` (`LAContext`) · `FileManager`
