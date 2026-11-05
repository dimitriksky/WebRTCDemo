import Foundation
import WebRTC

// Codable bridge between RTCSdpType (a C++ enum) and a plain Swift string.
// RTCSdpType can't conform to Codable directly — it's an ObjC enum from the WebRTC library.
enum SdpType: String, Codable {
    case offer, prAnswer, answer, rollback

    var rtcSdpType: RTCSdpType {
        switch self {
        case .offer:    return .offer
        case .answer:   return .answer
        case .prAnswer: return .prAnswer
        case .rollback: return .rollback
        }
    }
}

// Codable wrapper for RTCSessionDescription so it can travel over WebSocket as JSON.
struct SessionDescription: Codable {
    let sdp: String
    let type: SdpType

    init(from rtcSessionDescription: RTCSessionDescription) {
        self.sdp = rtcSessionDescription.sdp
        switch rtcSessionDescription.type {
        case .offer:    self.type = .offer
        case .answer:   self.type = .answer
        case .prAnswer: self.type = .prAnswer
        case .rollback: self.type = .rollback
        @unknown default: fatalError("Unknown RTCSdpType: \(rtcSessionDescription.type.rawValue)")
        }
    }

    var rtcSessionDescription: RTCSessionDescription {
        RTCSessionDescription(type: type.rtcSdpType, sdp: sdp)
    }
}
