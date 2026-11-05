import SwiftUI
import WebRTC

// SwiftUI wrapper for RTCMTLVideoView — the Metal-accelerated WebRTC video renderer.
// Usage:
//   RTCVideoView(track: webRTCClient.remoteVideoTrack)
//       .aspectRatio(16/9, contentMode: .fit)
struct RTCVideoView: UIViewRepresentable {

    let track: RTCVideoTrack?

    func makeUIView(context: Context) -> RTCMTLVideoView {
        let view = RTCMTLVideoView(frame: .zero)
        // scaleAspectFill fills the frame and crops edges — good for full-screen video.
        // Change to scaleAspectFit to letterbox/pillarbox instead.
        view.videoContentMode = .scaleAspectFill
        view.clipsToBounds = true
        return view
    }

    func updateUIView(_ uiView: RTCMTLVideoView, context: Context) {
        // Detach the renderer from the old track before attaching to the new one.
        // Skipping this causes the old track to keep sending frames here.
        if context.coordinator.currentTrack !== track {
            context.coordinator.currentTrack?.remove(uiView)
            track?.add(uiView)
            context.coordinator.currentTrack = track
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // Holds a reference to whichever track is currently rendering into the view,
    // so updateUIView can remove the renderer when the track changes.
    final class Coordinator {
        var currentTrack: RTCVideoTrack?

        deinit {
            // Track reference is cleaned up when the view is removed from the hierarchy.
            currentTrack = nil
        }
    }
}
