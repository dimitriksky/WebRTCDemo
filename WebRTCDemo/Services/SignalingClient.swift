import Foundation
import WebRTC
import Observation

@Observable
final class SignalingClient {

    // MARK: - Observable state

    enum ConnectionStatus {
        case disconnected
        case connecting
        case connected
    }

    private(set) var status: ConnectionStatus = .disconnected

    // MARK: - Private

    private let webRTCClient: WebRTCClient
    private let config: Config
    private var socketClient: WebSocketClient?

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - Init

    init(webRTCClient: WebRTCClient, config: Config) {
        self.webRTCClient = webRTCClient
        self.config = config

        // Forward locally gathered ICE candidates straight to the signaling server.
        webRTCClient.onLocalCandidate = { [weak self] candidate in
            self?.send(.candidate(IceCandidate(from: candidate)))
        }
    }

    // MARK: - Connect / Disconnect

    func connect() {
        guard status == .disconnected else { return }
        status = .connecting
        let socket = WebSocketClient(url: config.signalingServerURL)
        socketClient = socket
        socket.connect()

        Task { [weak self] in
            guard let self else { return }
            await self.handle(events: socket.events)
        }
    }

    func disconnect() {
        socketClient?.disconnect()
        socketClient = nil
        status = .disconnected
    }

    // MARK: - Event loop

    private func handle(events: AsyncStream<WebSocketClient.Event>) async {
        for await event in events {
            switch event {
            case .connected:
                await MainActor.run { status = .connected }
                print("SignalingClient: connected to \(config.signalingServerURL)")

            case .message(let data):
                await handleMessage(data)

            case .disconnected:
                await MainActor.run { status = .disconnected }
                print("SignalingClient: disconnected")
                await scheduleReconnect()
            }
        }
    }

    private func handleMessage(_ data: Data) async {
        guard let message = try? decoder.decode(Message.self, from: data) else {
            print("SignalingClient: could not decode message: \(String(data: data, encoding: .utf8) ?? "<binary>")")
            return
        }

        do {
            switch message {
            case .sdp(let sessionDescription):
                // The browser sent us an SDP offer. Create and send back an answer.
                // This is the entire callee flow in one call.
                let answer = try await webRTCClient.handleOffer(sessionDescription.rtcSessionDescription)
                send(.sdp(SessionDescription(from: answer)))
                print("SignalingClient: sent SDP answer")

            case .candidate(let iceCandidate):
                // A remote ICE candidate arrived — hand it to the peer connection
                // so it can try that network path.
                try await webRTCClient.set(remoteCandidate: iceCandidate.rtcIceCandidate)
            }
        } catch {
            print("SignalingClient: error handling message: \(error)")
        }
    }

    // MARK: - Send

    private func send(_ message: Message) {
        guard let data = try? encoder.encode(message) else {
            print("SignalingClient: could not encode message")
            return
        }
        socketClient?.send(data: data)
    }

    // MARK: - Reconnect

    private func scheduleReconnect() async {
        // Only reconnect if we weren't intentionally disconnected.
        guard status == .disconnected, socketClient != nil else { return }
        print("SignalingClient: reconnecting in 2s…")
        try? await Task.sleep(for: .seconds(2))
        connect()
    }
}
