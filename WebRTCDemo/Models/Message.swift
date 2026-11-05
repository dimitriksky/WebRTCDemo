import Foundation

// Every WebSocket message is one of two cases.
// The JSON envelope looks like:
//   { "type": "SessionDescription", "payload": { ... } }
//   { "type": "IceCandidate",       "payload": { ... } }
//
// The "type" string matches the Swift type name exactly — this keeps the
// encoder and decoder symmetric without needing a separate mapping table.
enum Message {
    case sdp(SessionDescription)
    case candidate(IceCandidate)
}

extension Message: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, payload
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case String(describing: SessionDescription.self):
            self = .sdp(try container.decode(SessionDescription.self, forKey: .payload))
        case String(describing: IceCandidate.self):
            self = .candidate(try container.decode(IceCandidate.self, forKey: .payload))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container,
                debugDescription: "Unknown message type: \(type)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .sdp(let sessionDescription):
            try container.encode(String(describing: SessionDescription.self), forKey: .type)
            try container.encode(sessionDescription, forKey: .payload)
        case .candidate(let iceCandidate):
            try container.encode(String(describing: IceCandidate.self), forKey: .type)
            try container.encode(iceCandidate, forKey: .payload)
        }
    }
}
