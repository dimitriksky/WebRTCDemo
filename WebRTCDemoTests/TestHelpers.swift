import Foundation

// Shared test data builders used across all test files.
// These produce JSON in the same format the browser sends over WebSocket.

func browserSdpJSON(type: String, sdp: String) -> Data {
    """
    {"type":"SessionDescription","payload":{"type":"\(type)","sdp":"\(sdp)"}}
    """.data(using: .utf8)!
}

func browserCandidateJSON(sdp: String, mid: String?, mLineIndex: Int) -> Data {
    let midValue = mid.map { "\"\($0)\"" } ?? "null"
    return """
    {"type":"IceCandidate","payload":{"sdp":"\(sdp)","sdpMLineIndex":\(mLineIndex),"sdpMid":\(midValue)}}
    """.data(using: .utf8)!
}
