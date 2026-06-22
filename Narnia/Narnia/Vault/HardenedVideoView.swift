//
//  HardenedVideoView.swift
//  Narnia
//
//  Privacy-hardened video viewer for vault playback (design spec §1, "Video
//  privacy hardening"). Video leaks in ways photos can't, so this view exists
//  precisely to shut those leaks off:
//
//   - Picture-in-Picture OFF (highest priority): without this, vault video
//     keeps playing in a floating window over other apps after you leave.
//   - AirPlay / external display OFF: a stray tap can't throw vault video to a
//     nearby TV.
//   - Audio STARTS MUTED: a tap in a quiet room shouldn't blast sound. The user
//     unmutes deliberately through the normal controls, and that choice sticks.
//
//  This requires `AVPlayerViewController` (wrapped in `UIViewControllerRepresentable`)
//  rather than SwiftUI's `VideoPlayer`, because disabling PiP is only reachable
//  through the controller. The `AVPlayer` is held in the Coordinator so SwiftUI
//  updates don't recreate it — recreating would reset the mute state and fight
//  the user's unmute.
//

import AVKit
import SwiftUI

/// Full-screen, privacy-hardened player for a single vault video. One route
/// inside the paging viewer shell; instantiate with the on-disk file URL of a
/// vault-owned video copy.
struct HardenedVideoView: View {
    private let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    var body: some View {
        HardenedPlayerRepresentable(fileURL: fileURL)
            .background(.black)
            .ignoresSafeArea()
    }
}

/// Bridges `AVPlayerViewController` into SwiftUI. All members are main-actor
/// isolated (the protocol requirements are `@MainActor`), and the only stored
/// reference-type state — the `AVPlayer` — lives in the Coordinator so it
/// survives view-graph updates rather than being rebuilt each time.
private struct HardenedPlayerRepresentable: UIViewControllerRepresentable {
    let fileURL: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(fileURL: fileURL)
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = context.coordinator.player

        // Picture-in-Picture OFF — both switches. `allowsPictureInPicturePlayback`
        // blocks the user/UI from starting PiP; `canStartPictureInPicture-
        // AutomaticallyFromInline` blocks the system from auto-starting it when
        // the app backgrounds. Both are required to fully prevent the floating
        // window that would otherwise keep vault video alive after you leave.
        controller.allowsPictureInPicturePlayback = false
        controller.canStartPictureInPictureAutomaticallyFromInline = false

        // Standard inline controls, on a black full-screen canvas.
        controller.showsPlaybackControls = true
        controller.videoGravity = .resizeAspect
        controller.view.backgroundColor = .black

        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        // Deliberately a no-op for the player and mute state. The player is
        // created once and owned by the Coordinator; reassigning it or
        // re-muting here on every SwiftUI update would discard the user's
        // unmute. Hardening flags are set once in `makeUIViewController` and
        // never need re-applying.
    }

    @MainActor
    final class Coordinator {
        let player: AVPlayer

        init(fileURL: URL) {
            player = AVPlayer(url: fileURL)

            // AirPlay / external display OFF — prevents routing vault video to
            // an external screen.
            player.allowsExternalPlayback = false

            // Audio STARTS muted. Set once, here — not in `updateUIView-
            // Controller` — so the user's later unmute through the standard
            // controls persists.
            player.isMuted = true
        }
    }
}
