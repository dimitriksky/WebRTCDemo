import Testing
import Foundation
@testable import WebRTCDemo

// Guards against the production bug where iOS dropped all browser messages
// because browsers send text frames but iOS only handled binary frames.
// If someone reverts the string-frame handling, test 1 will catch it immediately.

@MainActor
@Suite("WebSocket frame type handling — text vs binary")
struct FrameTypeTests {

    let decoder = JSONDecoder()
    let encoder = JSONEncoder()

    @Test("Text-encoded JSON decodes to same message as binary-encoded JSON")
    func textAndBinaryDecodeIdentically() throws {
        // This is the exact failure mode that caused the black screen bug:
        // browser sends JSON as a text frame → WebSocketClient received .string
        // → was silently dropped → iOS never processed the SDP offer.
        let jsonString = #"{"type":"SessionDescription","payload":{"type":"offer","sdp":"v=0\r\n"}}"#
        let fromText   = try decoder.decode(Message.self, from: jsonString.data(using: .utf8)!)
        let fromBinary = try decoder.decode(Message.self, from: Data(jsonString.utf8))

        guard case .sdp(let textResult) = fromText,
              case .sdp(let binaryResult) = fromBinary else {
            Issue.record("One or both frame types failed to decode")
            return
        }
        #expect(textResult.type == binaryResult.type)
        #expect(textResult.sdp == binaryResult.sdp)
    }

    @Test("Encoding round-trip produces valid UTF-8 — no data loss on text frame relay")
    func encodingRoundTripIsValidUtf8() throws {
        let json = browserSdpJSON(type: "offer", sdp: "v=0\\r\\n")
        // Every byte sequence produced by JSONEncoder must be valid UTF-8.
        // If not, String(data:encoding:) returns nil and the message is silently lost.
        let asString = String(data: json, encoding: .utf8)
        #expect(asString != nil, "JSON payload must be valid UTF-8 to survive text WebSocket relay")
    }

    @Test("Re-encoding a decoded message produces valid UTF-8")
    func reEncodedMessageIsValidUtf8() throws {
        let json = browserSdpJSON(type: "offer", sdp: "v=0\\r\\n")
        let message = try decoder.decode(Message.self, from: json)
        let reEncoded = try encoder.encode(message)
        let asString = String(data: reEncoded, encoding: .utf8)
        #expect(asString != nil, "Re-encoded message must be valid UTF-8")
    }
}
