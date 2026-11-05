import Testing
import Foundation
@testable import WebRTCDemo

// Scenario-driven tests describing real-world conditions the app will face.
// Test names describe the scenario, not the implementation — if behaviour
// changes, the name tells you exactly what broke.

@MainActor
@Suite("Known failure scenarios — real-world edge cases")
struct FailureScenarioTests {

    let decoder = JSONDecoder()

    @Test("Receiving SDP prAnswer type does not crash — transitional state some servers send")
    func prAnswerDoesNotCrash() throws {
        let message = try decoder.decode(Message.self, from: browserSdpJSON(type: "prAnswer", sdp: "v=0\\r\\n"))
        guard case .sdp(let desc) = message else { Issue.record("prAnswer failed to decode"); return }
        #expect(desc.type == .prAnswer)
    }

    @Test("Two consecutive ICE candidates decode independently — no shared state corruption")
    func consecutiveCandidatesAreIndependent() throws {
        // During ICE gathering, dozens of candidates arrive in rapid succession.
        // A shared mutable state bug would corrupt later candidates.
        let first = try decoder.decode(Message.self, from: browserCandidateJSON(
            sdp: "candidate:1 1 udp 1 192.168.0.1 5000 typ host", mid: "0", mLineIndex: 0))
        let second = try decoder.decode(Message.self, from: browserCandidateJSON(
            sdp: "candidate:2 1 udp 1 10.0.0.1 5001 typ srflx raddr 0.0.0.0 rport 0", mid: "0", mLineIndex: 0))

        guard case .candidate(let c1) = first, case .candidate(let c2) = second else {
            Issue.record("Failed to decode consecutive candidates"); return
        }
        #expect(c1.sdp != c2.sdp, "Consecutive candidates must not share data")
    }

    @Test("Null payload value does not crash — defensive check for bad server implementations")
    func nullPayloadThrowsNotCrash() {
        let json = #"{"type":"SessionDescription","payload":null}"#.data(using: .utf8)!
        #expect(throws: (any Error).self) {
            try decoder.decode(Message.self, from: json)
        }
    }

    @Test("Missing payload key does not crash")
    func missingPayloadKeyThrowsNotCrash() {
        let json = #"{"type":"SessionDescription"}"#.data(using: .utf8)!
        #expect(throws: (any Error).self) {
            try decoder.decode(Message.self, from: json)
        }
    }

    @Test("Missing type key does not crash")
    func missingTypeKeyThrowsNotCrash() {
        let json = #"{"payload":{"sdp":"v=0","type":"offer"}}"#.data(using: .utf8)!
        #expect(throws: (any Error).self) {
            try decoder.decode(Message.self, from: json)
        }
    }

    @Test("TURN candidate survives decode — needed once LAN testing phase ends")
    func turnCandidateDecodesCorrectly() throws {
        // Currently we test on LAN only. TURN candidates will appear once a TURN
        // server is configured. Their sdp string format differs from host candidates.
        let turnSdp = "candidate:3 1 tcp 1518222591 203.0.113.1 3478 typ relay raddr 192.168.0.9 rport 51000"
        let data = browserCandidateJSON(sdp: turnSdp, mid: "0", mLineIndex: 0)
        let message = try decoder.decode(Message.self, from: data)
        guard case .candidate(let c) = message else { Issue.record("TURN candidate failed to decode"); return }
        #expect(c.sdp.contains("typ relay"))
    }

    @Test("SignalingClient starts in disconnected state — no spurious connection on init")
    func signalingClientInitialStateIsDisconnected() {
        // If SignalingClient auto-connected on init, it would fire before the UI
        // is ready, triggering a WebSocket connection the user didn't request.
        let webRTCClient = WebRTCClient(iceServers: Config.default.iceServers)
        let client = SignalingClient(webRTCClient: webRTCClient, config: Config.default)
        #expect(client.status == .disconnected)
    }
}
