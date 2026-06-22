<div align="center">

# 🚪 Narnia

**A private, encrypted file vault for iOS — hidden behind the back of a wardrobe.**

[![Platform](https://img.shields.io/badge/platform-iOS-lightgrey.svg)](https://www.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)
[![UI](https://img.shields.io/badge/UI-SwiftUI-blue.svg)](https://developer.apple.com/xcode/swiftui/)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](#license)
[![Status](https://img.shields.io/badge/status-in%20design-yellow.svg)](#roadmap)

</div>

---

Narnia hides in plain sight. The app disguises itself as something ordinary (the "cover"), and behind it lives a separate, encrypted store — the **vault** — reachable only through a hidden door and biometric authentication. No icon, no label, no hint that a vault exists.

It started as a media vault (photos + HD video) and grew into a general **private file vault**: photos, video, documents, and arbitrary file types, organized in true nested folders. Think encrypted Files.app, not Photos.

> [!NOTE]
> Narnia is in the **design phase**. This repository currently holds design specs; implementation is starting. The authoritative design source is [`narnia-vault-design.md`](./narnia-vault-design.md).

## Table of Contents

- [Features](#features)
- [How It Works](#how-it-works)
  - [Getting In](#getting-in)
  - [Browsing](#browsing)
  - [Viewing](#viewing)
  - [Importing](#importing)
- [Security Model](#security-model)
- [Architecture](#architecture)
- [Tech Stack](#tech-stack)
- [Getting Started](#getting-started)
- [Roadmap](#roadmap)
- [Contributing](#contributing)
- [License](#license)

## Features

- 🚪 **Hidden entry** — one secret door (long-press + Face ID / Touch ID); no unlock UI anywhere
- 🔒 **Encrypted container** — vault files live in the app's own encrypted store, fully separate from the cover
- 🗂️ **True nested folders** — a real file-system model, not flat-with-albums
- 🖼️ **Any file type** — photos, video, documents, and a catch-all "other," all polymorphic
- 👁️ **Native viewing** — pinch-zoom photos, `AVPlayer` video, QuickLook for everything else
- 📥 **Permission-free import** — pull from Photos and Files with no system permission prompts
- 🛡️ **Privacy-hardened video** — PiP, AirPlay, and audio locked down so vault video can't leak

## How It Works

### Getting In

There is exactly **one way in**: long-press the wooden back-panel at the end of the Outerwear tab, confirmed by Face ID / Touch ID. No button, no password field, no "unlock" label — nothing that hints a vault exists.

### Browsing

- **Grid** — a unified, system-styled `LazyVGrid` in a `ScrollView`, following system light/dark.
- **Folders** — true nested directories. Each item has a single `parentFolderID`; one recursive view renders every level, showing sub-folders and loose media together.
- **Thumbnails** vary by type:

  | Type | Thumbnail |
  |------|-----------|
  | Photo | The image itself |
  | Video | Poster frame (`AVAssetImageGenerator`, ~1s in), cached, badged with a play glyph |
  | Document | Generic SF Symbol type icon — keeps content unreadable at a glance |
  | Other | Catch-all type icon |

- **Captions** — photos/videos show none; documents and folders show a filename/name. For documents the caption is the sole, load-bearing identifier.

### Viewing

The viewer routes by item type, wrapped in a common swipe-between-items shell:

| Item | Viewer |
|------|--------|
| Photo | Full-screen pinch-zoom image view |
| Video | `AVPlayer` via SwiftUI `VideoPlayer` |
| Everything else | **QuickLook** (`QLPreviewController`) — PDFs, Office/iWork, text, and fallback for any type |

**Video privacy hardening** (video leaks in ways photos can't):

- **Picture-in-Picture off** — otherwise vault video keeps playing in a floating window after you leave the app
- **AirPlay / external display off** — a stray tap shouldn't throw video to a nearby TV
- **Audio starts muted** — the user unmutes deliberately

### Importing

Two sources in v1, both out-of-process with **no permission prompt**:

- **Photos** → `PHPickerViewController` — returns only selected items
- **Files / docs** → `.fileImporter` — returns security-scoped URLs

Import targets the current folder. Whether to remove an original afterward is a one-time, best-effort preference ("remove originals *when possible*").

> [!IMPORTANT]
> **Hard ordering rule:** only delete an original *after* the vault copy is confirmed written to disk — never the reverse. A failed copy plus a successful delete loses the file.

| Source | Removal behavior |
|--------|------------------|
| Photos original | App can *attempt* removal, but iOS always shows its own deletion confirmation |
| Document-picker original | Removable only if write scope was granted |
| Vault-owned copies | Deleted silently via `FileManager`, no prompt ever |

## Security Model

Narnia uses a **fresh-start-only** session: you authenticate **once per app lifetime**. Once inside, you stay inside — backgrounding, app-switching, notifications, and auto-lock do *not* eject you or re-prompt. The vault re-locks only on a **cold launch** (full process termination).

> [!WARNING]
> **Deliberate tradeoff.** Because the session survives backgrounding, anyone who reopens the app while it's still in memory — e.g. a person you hand your unlocked phone to — lands directly inside the vault. This effectively reduces protection to the device passcode. A *Face-ID-on-return* alternative was considered and the fresh-start model chosen anyway. See [the spec](./narnia-vault-design.md#3-security--session-model) for full reasoning.

Storage principles:

- Vault files are copied into the app's own **encrypted container**, in a store entirely separate from cover/closet data — the two never reference each other.
- The app has silent, full control over vault-owned files. The only OS-mandated confirmation anywhere is removing an *original* from the Photos library.

## Architecture

```
Cover (disguise)  ──long-press + Face ID──▶  Vault
                                              │
        ┌─────────────────────┬───────────────┼───────────────────┐
        ▼                     ▼               ▼                   ▼
   Recursive grid        Type-routed      Import pickers     Encrypted
   (nested folders)        viewer       (Photos / Files)     container
   LazyVGrid          Image/Video/QL    PHPicker/.fileImporter   FileManager
```

The storage and folder layers are **type-agnostic** — a file is a file. Only the two ends differ by type: how items are displayed (thumbnails/captions) and how they're opened (viewer routing).

## Tech Stack

- **Language:** Swift
- **UI:** SwiftUI
- **Frameworks:** `LazyVGrid` · `AVFoundation` (`AVAssetImageGenerator`, `AVPlayer`) · `AVKit` (`VideoPlayer`) · `QuickLook` (`QLPreviewController`) · `PhotosUI` (`PHPickerViewController`) · `LocalAuthentication` (`LAContext`) · `FileManager`

## Getting Started

> [!NOTE]
> Implementation has not yet begun — these steps describe the intended setup.

**Requirements**

- Xcode 15+
- iOS 17+ device or simulator (Face ID / Touch ID requires a physical device or simulator with enrolled biometrics)

**Build**

```bash
git clone git@github.com:LiLiKazine/Narnia.git
cd Narnia
open Narnia.xcodeproj
```

Then select a target device and run (`⌘R`).

## Roadmap

- [x] Core vault: encrypted container, nested folders, grid
- [x] Type-routed viewer (photo / video / QuickLook)
- [x] Import from Photos and Files
- [x] Hidden-door entry + biometric auth
- [x] Video privacy hardening (PiP / AirPlay / mute)
- [x] **Quick-exit / panic** — explicit in-app exit *(flip-face-down-to-lock deferred)*
- [x] **Realm settings screen** — originals preference *(security toggles to follow)*
- [ ] **"Hide names" toggle** — mitigate on-screen-text leak from captions
- [ ] Camera-direct-into-vault *(stretch)*
- [ ] Share extension for importing from other apps *(stretch)*

## Contributing

Contributions are welcome! Since the project is in its design phase, the best place to start is reading [`narnia-vault-design.md`](./narnia-vault-design.md) and opening an issue to discuss before submitting a PR.

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Commit your changes
4. Open a pull request

## License

Distributed under the MIT License. See [`LICENSE`](./LICENSE) for details.
