# WebRTCDemo

An iOS app (iPhone + iPad) that receives a live video stream from a Mac browser over WebRTC. Built with SwiftUI and Google's WebRTC library via Swift Package Manager.

The scenario it models: a camera source (the browser) streams video to a passive iOS viewer. The iOS app is callee-only — it never initiates the call. The browser connects, sends an SDP offer, and the iPhone renders the incoming stream.

---

## Architecture

```
Mac Browser (camera.html)        Node.js Server (app.js)          iOS App
        │                               │                              │
        │── WebSocket connect ─────────▶│                              │
        │                               │◀──── WebSocket connect ──────│
        │── SDP offer ────────────────▶│──── broadcast ──────────────▶│
        │                               │◀──── SDP answer ─────────────│
        │◀──────────────── broadcast ───│                              │
        │── ICE candidates ───────────▶│──── broadcast ──────────────▶│
        │◀──────────────── broadcast ───│◀──── ICE candidates ──────── │
        │                               │                              │
        │════════════ P2P video stream (WebRTC) ══════════════════════▶│
```

**Signaling server** — a 24-line Node.js WebSocket relay that broadcasts every message to all other connected clients. No rooms, no routing logic.

**Transport** — local Wi-Fi only (no TURN server configured). Both devices must be on the same network.

---

## Requirements

- **Mac** with Node.js installed (`node --version` to verify; install from [nodejs.org](https://nodejs.org) if needed)
- **Xcode 15+**
- **iOS device** (iPhone or iPad) on the same Wi-Fi network as the Mac — the simulator cannot receive WebRTC video
- **Safari or Chrome** on the Mac for the browser camera page

---

## Setup

### 1 — Find your Mac's local IP address

Go to **System Settings → Wi-Fi → Details** (next to your active network) → copy the **IP Address**.  
It will look like `192.168.x.x` or `10.0.x.x`. You will need this in steps 3 and 4.

---

### 2 — Start the signaling server

Open a terminal and run:

```bash
cd path/to/WebRTCDemo/signaling
npm install
npm start
```

You should see:
```
Signaling server is now listening on port 8080
```

Leave this terminal open for the duration of testing.

---

### 3 — Open the browser camera page

Open `signaling/camera.html` in Safari or Chrome on your Mac.

```bash
open path/to/WebRTCDemo/signaling/camera.html
```

Click **Start Camera & Connect**. The browser will:
- Request camera and microphone access — grant both
- Show a live preview of your Mac camera
- Connect to the signaling server

Status should read: **Signaling connected — waiting for iOS peer…**

The **Resend Offer** button will appear — do not click it yet.

---

### 4 — Build and run the iOS app

1. Open `WebRTCDemo.xcodeproj` in Xcode
2. Select your iPhone or iPad as the run destination
3. In `WebRTCDemo/Config.swift`, the default IP is a placeholder — you can leave it and change it at runtime in the app's UI
4. Build and run (`⌘R`)
5. In the app, replace the IP field with your Mac's local IP from step 1
6. Tap **Connect**
7. Wait for the status badge to turn green and show **Connected**

---

### 5 — Start the stream

Go back to the browser and click **Resend Offer**.

The browser status should progress through:
```
SDP offer sent — waiting for answer…
SDP answer received — ICE connecting…
ICE: connected
```

The iOS app will display the Mac camera feed full-screen.

> **Why Resend Offer?** The signaling server is a simple broadcast relay with no concept of "who is online". If the browser sends its offer before the iPhone connects, the offer goes to nobody. Clicking Resend Offer after the iPhone shows Connected avoids this race condition.

---

## Running the tests

The test suite uses Swift Testing and covers signaling protocol decoding, WebSocket frame type handling, config validation, and real-world failure scenarios.

Run from Xcode with `⌘U`, or select individual suites in the Test Navigator:

| File | What it covers |
|---|---|
| `SignalingProtocolTests` | JSON decoding for all browser message types |
| `FrameTypeTests` | Text vs binary WebSocket frame handling |
| `ConfigTests` | Signaling URL and ICE server validation |
| `FailureScenarioTests` | Edge cases: null sdpMid, TURN candidates, bad payloads |

> Tests run on the simulator — no device or running server required.

---

## Project structure

```
WebRTCDemo/
├── WebRTCDemo/
│   ├── Config.swift                  # Signaling URL + ICE servers
│   ├── ContentView.swift             # Main SwiftUI UI
│   ├── Models/
│   │   ├── Message.swift             # Codable wire format envelope
│   │   ├── SessionDescription.swift  # SDP wrapper
│   │   └── IceCandidate.swift        # ICE candidate wrapper
│   ├── Services/
│   │   ├── WebSocketClient.swift     # URLSession WebSocket, AsyncStream
│   │   ├── SignalingClient.swift     # Offer/answer flow, reconnect logic
│   │   └── WebRTCClient.swift        # RTCPeerConnection, video track
│   └── Views/
│       └── RTCVideoView.swift        # UIViewRepresentable for RTCMTLVideoView
├── WebRTCDemoTests/
│   ├── TestHelpers.swift
│   ├── SignalingProtocolTests.swift
│   ├── FrameTypeTests.swift
│   ├── ConfigTests.swift
│   └── FailureScenarioTests.swift
└── signaling/
    ├── app.js                        # Node.js WebSocket relay server
    ├── package.json
    └── camera.html                   # Browser camera source / robot simulator
```

---

## Troubleshooting

**App shows "Connected" but no video appears**  
The most common cause is a timing race. Click **Resend Offer** in the browser after the app shows Connected.

**Browser status stays at "SDP offer sent — waiting for answer"**  
Open the browser's developer console (⌥⌘I → Console). If you see no `[ws ←]` entries after clicking Resend Offer, the iOS app is not receiving the offer. Confirm both devices are on the same Wi-Fi network and the signaling server is running.

**iOS app stays on "Connecting…" indefinitely**  
The WebSocket cannot reach the server. Verify:
- The IP in the app matches your Mac's current local IP (it changes when you join a different network)
- The signaling server is running on port 8080
- No firewall is blocking port 8080 on the Mac (`System Settings → Network → Firewall`)

**Camera permission denied in browser**  
Safari requires the page to be served over HTTPS or from `localhost` to allow camera access. Opening a local file directly works in Chrome; in Safari you may need to run a local server:
```bash
cd path/to/WebRTCDemo/signaling
npx serve .
```
Then open `http://localhost:3000/camera.html`.

---

## Notes

- The app is callee-only — it never sends video or initiates a call
- Audio is received alongside video but plays silently by default (no speaker controls in this prototype)
- TURN server support is not configured; the connection will fail if both peers are behind strict NAT (e.g. different mobile networks or some corporate Wi-Fi)
