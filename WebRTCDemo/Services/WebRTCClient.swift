import Foundation
import WebRTC
import Observation

@Observable
final class WebRTCClient: NSObject {

    // MARK: - Observable state

    // The ICE connection state drives the UI status indicator.
    // Values: .new → .checking → .connected → .completed (or .failed/.disconnected)
    private(set) var connectionState: RTCIceConnectionState = .new

    // Set once the remote peer's video track is received and ready to render.
    private(set) var remoteVideoTrack: RTCVideoTrack?

    // MARK: - Non-observed

    // SignalingClient sets this to forward locally gathered ICE candidates over WebSocket.
    // @ObservationIgnored because closures can't and shouldn't be observed.
    @ObservationIgnored
    var onLocalCandidate: ((RTCIceCandidate) -> Void)?

    // MARK: - Private

    // The factory is expensive to create and must only exist once per process.
    // RTCInitializeSSL() must be called before any peer connection is created.
    private static let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        return RTCPeerConnectionFactory(
            encoderFactory: RTCDefaultVideoEncoderFactory(),
            decoderFactory: RTCDefaultVideoDecoderFactory()
        )
    }()

    private let peerConnection: RTCPeerConnection

    // RTCAudioSession is WebRTC's wrapper around AVAudioSession.
    // It must be configured before the peer connection starts sending/receiving audio.
    private let rtcAudioSession = RTCAudioSession.sharedInstance()

    // Constraints passed to answer() — tells the remote side
    // that we want to receive both audio and video.
    private let mediaConstraints = RTCMediaConstraints(
        mandatoryConstraints: [
            kRTCMediaConstraintsOfferToReceiveAudio: kRTCMediaConstraintsValueTrue,
            kRTCMediaConstraintsOfferToReceiveVideo: kRTCMediaConstraintsValueTrue,
        ],
        optionalConstraints: nil
    )

    // MARK: - Init

    init(iceServers: [String]) {
        let config = RTCConfiguration()
        config.iceServers = [RTCIceServer(urlStrings: iceServers)]

        // Unified Plan is the modern SDP format (replaces legacy Plan B).
        // Required for multi-track sessions and browser interoperability.
        config.sdpSemantics = .unifiedPlan

        // Gather candidates continuously so WebRTC adapts when the network
        // interface changes (e.g. Wi-Fi ↔ cellular handoff).
        config.continualGatheringPolicy = .gatherContinually

        // DtlsSrtpKeyAgreement MUST be true to connect with browsers.
        // Browsers enforce DTLS-SRTP encryption and will reject the connection otherwise.
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: ["DtlsSrtpKeyAgreement": kRTCMediaConstraintsValueTrue]
        )

        guard let pc = WebRTCClient.factory.peerConnection(
            with: config,
            constraints: constraints,
            delegate: nil
        ) else {
            fatalError("Failed to create RTCPeerConnection")
        }
        peerConnection = pc
        super.init()

        peerConnection.delegate = self
        addMediaTracks()
        configureAudioSession()
    }

    // MARK: - Signaling

    // Called when we receive an SDP offer from the browser.
    // Sets it as the remote description, then creates and returns our answer.
    func handleOffer(_ sdp: RTCSessionDescription) async throws -> RTCSessionDescription {
        try await setRemoteDescription(sdp)
        return try await createAnswer()
    }

    func set(remoteCandidate: RTCIceCandidate) async throws {
        try await peerConnection.add(remoteCandidate)
    }

    // MARK: - Private signaling helpers

    private func setRemoteDescription(_ sdp: RTCSessionDescription) async throws {
        try await peerConnection.setRemoteDescription(sdp)
    }

    private func createAnswer() async throws -> RTCSessionDescription {
        let sdp = try await peerConnection.answer(for: mediaConstraints)
        try await peerConnection.setLocalDescription(sdp)
        return sdp
    }

    // MARK: - Media setup

    private func addMediaTracks() {
        let streamId = "remoteStream"

        // Add a local audio track. We won't capture from the mic but the
        // transceiver this creates is needed for the remote audio track to arrive.
        let audioSource = WebRTCClient.factory.audioSource(with: RTCMediaConstraints(
            mandatoryConstraints: nil, optionalConstraints: nil
        ))
        let audioTrack = WebRTCClient.factory.audioTrack(with: audioSource, trackId: "audio0")
        peerConnection.add(audioTrack, streamIds: [streamId])

        // Add a local video track. Same reason — the transceiver it creates
        // is where the remote video track will be received.
        let videoSource = WebRTCClient.factory.videoSource()
        let videoTrack = WebRTCClient.factory.videoTrack(with: videoSource, trackId: "video0")
        peerConnection.add(videoTrack, streamIds: [streamId])

        // Grab the remote video track from the receiver side of the video transceiver.
        // This is nil until the remote SDP is applied, so we also update it in
        // peerConnection(_:didStartReceivingOn:) below.
        remoteVideoTrack = peerConnection.transceivers
            .first { $0.mediaType == .video }?
            .receiver.track as? RTCVideoTrack
    }

    private func configureAudioSession() {
        rtcAudioSession.lockForConfiguration()
        defer { rtcAudioSession.unlockForConfiguration() }
        do {
            try rtcAudioSession.setCategory(AVAudioSession.Category.playAndRecord)
            try rtcAudioSession.setMode(AVAudioSession.Mode.voiceChat)
        } catch {
            print("WebRTCClient: failed to configure AVAudioSession: \(error)")
        }
    }
}

// MARK: - RTCPeerConnectionDelegate

extension WebRTCClient: RTCPeerConnectionDelegate {

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange state: RTCIceConnectionState) {
        print("ICE connection state → \(state.debugDescription)")
        // RTCPeerConnectionDelegate callbacks fire on WebRTC's internal thread.
        // Dispatch to main so @Observable property updates are picked up by SwiftUI.
        DispatchQueue.main.async { self.connectionState = state }
    }

    // Called when a new local ICE candidate is ready to be sent to the remote peer.
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        onLocalCandidate?(candidate)
    }

    // Called when a transceiver starts receiving media — the remote track is now live.
    func peerConnection(_ peerConnection: RTCPeerConnection, didStartReceivingOn transceiver: RTCRtpTransceiver) {
        guard transceiver.mediaType == .video else { return }
        let track = transceiver.receiver.track as? RTCVideoTrack
        DispatchQueue.main.async {
            self.remoteVideoTrack = track
            print("WebRTCClient: remote video track ready")
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        print("Signaling state → \(stateChanged)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
}

// MARK: - RTCIceConnectionState description

extension RTCIceConnectionState {
    var debugDescription: String {
        switch self {
        case .new:          return "new"
        case .checking:     return "checking"
        case .connected:    return "connected"
        case .completed:    return "completed"
        case .failed:       return "failed"
        case .disconnected: return "disconnected"
        case .closed:       return "closed"
        case .count:        return "count"
        @unknown default:   return "unknown"
        }
    }
}
