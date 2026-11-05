import SwiftUI
import WebRTC

struct ContentView: View {

    // MARK: - State

    @State private var serverIP: String = "192.168.0.9"
    @State private var webRTCClient = WebRTCClient(iceServers: Config.default.iceServers)
    @State private var signalingClient: SignalingClient?

    private var isConnected: Bool {
        signalingClient?.status == .connected
    }

    private var isConnecting: Bool {
        signalingClient?.status == .connecting
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            videoLayer

            VStack {
                Spacer()
                controlPanel
                    .padding(.bottom, 40)
            }
        }
    }

    // MARK: - Video layer

    @ViewBuilder
    private var videoLayer: some View {
        if let track = webRTCClient.remoteVideoTrack {
            RTCVideoView(track: track)
                .ignoresSafeArea()
                .transition(.opacity)
        } else {
            placeholderView
        }
    }

    private var placeholderView: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 56))
                .foregroundStyle(.white.opacity(0.3))
            Text("Waiting for stream…")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    // MARK: - Control panel

    private var controlPanel: some View {
        VStack(spacing: 12) {
            statusBadge

            HStack(spacing: 12) {
                TextField("Server IP", text: $serverIP)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.decimalPad)
                    .autocorrectionDisabled()
                    .disabled(isConnected || isConnecting)
                    .frame(maxWidth: 200)

                connectButton
            }
            .padding(.horizontal, 24)
        }
        .padding(.vertical, 16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 24)
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .overlay {
                    if isConnecting {
                        Circle()
                            .stroke(statusColor.opacity(0.4), lineWidth: 1)
                            .scaleEffect(1.8)
                            .animation(.easeInOut(duration: 0.8).repeatForever(), value: isConnecting)
                    }
                }
            Text(statusLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var connectButton: some View {
        Button {
            isConnected || isConnecting ? handleDisconnect() : handleConnect()
        } label: {
            Group {
                if isConnecting {
                    ProgressView()
                        .tint(.white)
                        .frame(width: 20, height: 20)
                } else {
                    Text(isConnected ? "Disconnect" : "Connect")
                        .fontWeight(.semibold)
                }
            }
            .frame(width: 110, height: 36)
        }
        .buttonStyle(.borderedProminent)
        .tint(isConnected ? .red : .blue)
        .animation(.default, value: isConnected)
    }

    // MARK: - Actions

    private func handleConnect() {
        guard let url = URL(string: "ws://\(serverIP):8080") else { return }
        let config = Config(signalingServerURL: url, iceServers: Config.default.iceServers)
        // Create a fresh WebRTCClient for each new call attempt.
        webRTCClient = WebRTCClient(iceServers: config.iceServers)
        let client = SignalingClient(webRTCClient: webRTCClient, config: config)
        signalingClient = client
        client.connect()
    }

    private func handleDisconnect() {
        signalingClient?.disconnect()
        signalingClient = nil
        webRTCClient = WebRTCClient(iceServers: Config.default.iceServers)
    }

    // MARK: - Helpers

    private var statusLabel: String {
        switch signalingClient?.status {
        case .connected:    return "Connected"
        case .connecting:   return "Connecting…"
        case .disconnected: return "Disconnected"
        case nil:           return "Idle"
        }
    }

    private var statusColor: Color {
        switch signalingClient?.status {
        case .connected:    return .green
        case .connecting:   return .orange
        case .disconnected: return .red
        case nil:           return .gray
        }
    }
}

#Preview {
    ContentView()
}
