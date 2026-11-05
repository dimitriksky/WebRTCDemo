import Testing
import Foundation
@testable import WebRTCDemo

// What matters: iOS correctly interprets every message the browser can send.
// @MainActor required because SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor in the
// app target makes all Codable conformances main-actor-isolated.

@MainActor
@Suite("Signaling protocol — decoding browser messages")
struct SignalingProtocolTests {

    let decoder = JSONDecoder()
    let encoder = JSONEncoder()

    @Test("Decodes SDP offer from browser")
    func decodesSdpOffer() throws {
        let message = try decoder.decode(Message.self, from: browserSdpJSON(type: "offer", sdp: "v=0\\r\\n"))
        guard case .sdp(let desc) = message else { Issue.record("Expected .sdp case"); return }
        #expect(desc.type == .offer)
    }

    @Test("Decodes SDP answer from browser")
    func decodesSdpAnswer() throws {
        let message = try decoder.decode(Message.self, from: browserSdpJSON(type: "answer", sdp: "v=0\\r\\n"))
        guard case .sdp(let desc) = message else { Issue.record("Expected .sdp case"); return }
        #expect(desc.type == .answer)
    }

    @Test("Decodes ICE candidate with sdpMid present — Chrome / Firefox format")
    func decodesIceCandidateWithMid() throws {
        let data = browserCandidateJSON(
            sdp: "candidate:1 1 udp 2122260223 192.168.0.9 51000 typ host", mid: "0", mLineIndex: 0)
        let message = try decoder.decode(Message.self, from: data)
        guard case .candidate(let c) = message else { Issue.record("Expected .candidate case"); return }
        #expect(c.sdpMid == "0")
        #expect(c.sdpMLineIndex == 0)
    }

    @Test("Decodes ICE candidate with null sdpMid — Safari omits this field")
    func decodesIceCandidateWithNilMid() throws {
        let data = browserCandidateJSON(
            sdp: "candidate:1 1 udp 2122260223 192.168.0.9 51000 typ host", mid: nil, mLineIndex: 0)
        let message = try decoder.decode(Message.self, from: data)
        guard case .candidate(let c) = message else { Issue.record("Expected .candidate case"); return }
        #expect(c.sdpMid == nil, "Safari sends null sdpMid — must not crash or corrupt")
    }

    @Test("ICE candidate for video track (sdpMLineIndex: 1) decodes correctly")
    func decodesVideoCandidateIndex() throws {
        let data = browserCandidateJSON(
            sdp: "candidate:2 1 udp 2122194687 192.168.0.9 51002 typ host", mid: "1", mLineIndex: 1)
        let message = try decoder.decode(Message.self, from: data)
        guard case .candidate(let c) = message else { return }
        #expect(c.sdpMLineIndex == 1)
    }

    @Test("SDP CRLF line endings survive encoding round-trip")
    func sdpCrlfSurvivesRoundTrip() throws {
        // SDP spec mandates CRLF (\\r\\n). A UTF-8 encoding bug would silently
        // strip or corrupt the \\r, breaking SDP parsing on the WebRTC side.
        let json = #"{"type":"SessionDescription","payload":{"type":"offer","sdp":"v=0\r\no=- 123 2 IN IP4 127.0.0.1\r\n"}}"#.data(using: .utf8)!
        let message = try decoder.decode(Message.self, from: json)
        let reDecoded = try decoder.decode(Message.self, from: try encoder.encode(message))
        guard case .sdp(let original) = message, case .sdp(let result) = reDecoded else { return }
        #expect(result.sdp == original.sdp)
    }

    @Test("Server sends unknown message type — throws instead of silently ignoring")
    func unknownMessageTypeThrows() {
        // Silent no-op would look identical to a lost ICE candidate from the app's perspective.
        let json = #"{"type":"Ping","payload":{}}"#.data(using: .utf8)!
        #expect(throws: (any Error).self) {
            try decoder.decode(Message.self, from: json)
        }
    }

    @Test("Malformed JSON does not crash — throws DecodingError")
    func malformedJsonThrows() {
        #expect(throws: (any Error).self) {
            try decoder.decode(Message.self, from: Data([0xFF, 0xFE, 0x00, 0x01]))
        }
    }

    @Test("Empty payload does not crash — throws DecodingError")
    func emptyDataThrows() {
        #expect(throws: (any Error).self) {
            try decoder.decode(Message.self, from: Data())
        }
    }

    @Test("Server adds extra fields to payload — unknown fields are ignored")
    func extraFieldsInPayloadAreIgnored() throws {
        // Future protocol versions or different signaling server implementations
        // may add fields like roomId or timestamp. Must not break decoding.
        let json = """
        {"type":"SessionDescription","payload":{"sdp":"v=0\\r\\n","type":"offer","roomId":"abc","timestamp":1699999999}}
        """.data(using: .utf8)!
        let message = try decoder.decode(Message.self, from: json)
        guard case .sdp(let desc) = message else { Issue.record("Extra fields caused decode failure"); return }
        #expect(desc.type == .offer)
    }

    @Test("Very large SDP does not crash decoder — real SDPs can exceed 10KB")
    func largeSdpDoesNotCrash() throws {
        let largeSdp = String(repeating: "a=fmtp:111 minptime=10;useinbandfec=1\\r\\n", count: 500)
        let json = """
        {"type":"SessionDescription","payload":{"type":"offer","sdp":"\(largeSdp)"}}
        """.data(using: .utf8)!
        let message = try decoder.decode(Message.self, from: json)
        guard case .sdp(let desc) = message else { return }
        #expect(!desc.sdp.isEmpty)
    }

    @Test("ICE candidate with empty sdp signals end of gathering — must not crash")
    func emptyCandidateSdpIsHandled() throws {
        // Some browsers send a final candidate event with an empty string to
        // signal that ICE gathering is complete.
        let data = browserCandidateJSON(sdp: "", mid: "0", mLineIndex: 0)
        let message = try decoder.decode(Message.self, from: data)
        guard case .candidate(let c) = message else { Issue.record("Empty candidate sdp caused decode failure"); return }
        #expect(c.sdp == "")
    }
}
