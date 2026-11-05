import Foundation

final class WebSocketClient: NSObject {

    enum Event {
        case connected
        case message(Data)
        case disconnected
    }

    // Callers iterate over this stream to receive connection events and data.
    // The stream finishes when the socket is disconnected or disconnect() is called.
    let events: AsyncStream<Event>

    private var continuation: AsyncStream<Event>.Continuation?
    private var webSocketTask: URLSessionWebSocketTask?
    private let url: URL

    // Delegate queue nil → callbacks arrive on URLSession's internal serial queue.
    private lazy var urlSession = URLSession(
        configuration: .default,
        delegate: self,
        delegateQueue: nil
    )

    init(url: URL) {
        self.url = url
        // AsyncStream.init closure is called synchronously, so capturing
        // the continuation here before super.init() is safe.
        var captured: AsyncStream<Event>.Continuation?
        events = AsyncStream { captured = $0 }
        super.init()
        continuation = captured
    }

    func connect() {
        let task = urlSession.webSocketTask(with: url)
        webSocketTask = task
        task.resume()
        receiveNext()
    }

    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        continuation?.finish()
    }

    func send(data: Data) {
        webSocketTask?.send(.data(data)) { _ in }
    }

    // URLSession WebSocket API is pull-based: you call receive() once and
    // it fires your closure with the next message. To keep receiving, you
    // call receive() again inside the closure — forming a loop without blocking.
    private func receiveNext() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(.data(let data)):
                self.continuation?.yield(.message(data))
                self.receiveNext()
            case .success(.string):
                // The Node.js server sends binary frames; strings are unexpected.
                // Skip and keep listening rather than failing hard.
                self.receiveNext()
            case .failure:
                self.continuation?.yield(.disconnected)
                self.continuation?.finish()
            @unknown default:
                self.receiveNext()
            }
        }
    }
}

extension WebSocketClient: URLSessionWebSocketDelegate {

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        continuation?.yield(.connected)
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        continuation?.yield(.disconnected)
        continuation?.finish()
    }
}
