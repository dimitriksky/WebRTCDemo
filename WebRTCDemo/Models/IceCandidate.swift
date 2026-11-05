import Foundation
import WebRTC

// Codable wrapper for RTCIceCandidate so it can travel over WebSocket as JSON.
//
// sdpMLineIndex: which media section in the SDP this candidate belongs to
//   (0 = audio, 1 = video in a typical offer).
// sdpMid: human-readable label for that media section ("audio", "video", or "0", "1").
// sdp: the candidate string itself, e.g. "candidate:1 1 udp 2122260223 192.168.0.9 51000 typ host ..."
struct IceCandidate: Codable {
    let sdp: String
    let sdpMLineIndex: Int32
    let sdpMid: String?

    init(from iceCandidate: RTCIceCandidate) {
        self.sdp = iceCandidate.sdp
        self.sdpMLineIndex = iceCandidate.sdpMLineIndex
        self.sdpMid = iceCandidate.sdpMid
    }

    var rtcIceCandidate: RTCIceCandidate {
        RTCIceCandidate(sdp: sdp, sdpMLineIndex: sdpMLineIndex, sdpMid: sdpMid)
    }
}
