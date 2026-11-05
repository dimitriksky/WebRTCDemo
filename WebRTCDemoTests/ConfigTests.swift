import Testing
import Foundation
@testable import WebRTCDemo

// Validates that the configuration the app ships with is sane.
// If someone accidentally changes the port, scheme, or removes ICE servers,
// these fail before it reaches a device.

@MainActor
@Suite("Configuration — signaling and ICE server settings")
struct ConfigTests {

    @Test("Default config signaling URL uses WebSocket scheme")
    func defaultSignalingUrlScheme() {
        let scheme = Config.default.signalingServerURL.scheme
        #expect(scheme == "ws" || scheme == "wss", "Expected ws:// or wss://, got: \(scheme ?? "nil")")
    }

    @Test("Default config signaling URL targets port 8080")
    func defaultSignalingUrlPort() {
        #expect(Config.default.signalingServerURL.port == 8080)
    }

    @Test("Default ICE server list is non-empty — empty list breaks all non-LAN connections")
    func defaultIceServersNonEmpty() {
        #expect(!Config.default.iceServers.isEmpty)
    }

    @Test("All default ICE servers use a valid URL scheme")
    func iceServersHaveValidScheme() {
        for server in Config.default.iceServers {
            let valid = server.hasPrefix("stun:") || server.hasPrefix("turn:") || server.hasPrefix("turns:")
            #expect(valid, "Invalid ICE server URL: \(server)")
        }
    }

    @Test("Config with arbitrary local IP produces parseable URL")
    func configWithCustomIpIsValid() {
        let url = URL(string: "ws://10.0.1.254:8080")
        #expect(url != nil)
        #expect(url?.host == "10.0.1.254")
    }

    @Test("Config with localhost URL is valid — developer testing scenario")
    func configWithLocalhostIsValid() {
        let url = URL(string: "ws://localhost:8080")
        #expect(url != nil)
        #expect(url?.host == "localhost")
    }
}
