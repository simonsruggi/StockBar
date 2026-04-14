import Foundation
import SwiftProtobuf

@MainActor
final class WebSocketService: NSObject, ObservableObject {
    static let shared = WebSocketService()

    @Published var isConnected = false

    private var webSocketTask: URLSessionWebSocketTask?
    private var heartbeatTimer: Timer?
    private var subscribedSymbols: [String] = []
    private var reconnectAttempts = 0
    private var reconnectTimer: Timer?

    /// Called on main actor whenever a new tick arrives
    var onTick: ((Yaticker) -> Void)?

    private static let endpoint = URL(string: "wss://streamer.finance.yahoo.com/?version=2")!
    private static let heartbeatInterval: TimeInterval = 15
    private static let maxReconnectDelay: TimeInterval = 120

    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    private override init() {
        super.init()
    }

    // MARK: - Public API

    func connect(symbols: [String]) {
        guard !symbols.isEmpty else { return }
        subscribedSymbols = symbols
        reconnectAttempts = 0
        openConnection()
    }

    func updateSymbols(_ symbols: [String]) {
        let oldSet = Set(subscribedSymbols)
        let newSet = Set(symbols)
        subscribedSymbols = symbols

        guard isConnected, webSocketTask != nil else {
            // Not connected yet — symbols will be sent on connect
            return
        }

        let toUnsub = oldSet.subtracting(newSet)
        let toSub = newSet.subtracting(oldSet)

        if !toUnsub.isEmpty {
            sendJSON(["unsubscribe": Array(toUnsub)])
        }
        if !toSub.isEmpty {
            sendJSON(["subscribe": Array(toSub)])
        }
    }

    func disconnect() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
    }

    // MARK: - Connection

    private func openConnection() {
        disconnect()

        let task = urlSession.webSocketTask(with: Self.endpoint)
        webSocketTask = task
        task.resume()
        // Subscribe + receive will start in didOpenWithProtocol delegate
    }

    // MARK: - Messaging

    private func sendJSON(_ dict: [String: [String]]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else { return }
        webSocketTask?.send(.string(str)) { error in
            if let error {
                print("[WSS] Send error: \(error.localizedDescription)")
            }
        }
    }

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success(let message):
                    self.handleMessage(message)
                    self.receiveMessage() // keep listening
                case .failure(let error):
                    print("[WSS] Receive error: \(error.localizedDescription)")
                    self.handleDisconnect()
                }
            }
        }
    }

    private struct WSSMessage: Decodable {
        let type: String?
        let message: String? // base64-encoded protobuf
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        let text: String
        switch message {
        case .string(let t): text = t
        case .data(let d):
            guard let t = String(data: d, encoding: .utf8) else { return }
            text = t
        @unknown default: return
        }

        // Yahoo WSS v2 wraps protobuf in JSON: {"type":"pricing","message":"<base64>"}
        guard let jsonData = text.data(using: .utf8),
              let wssMsg = try? JSONDecoder().decode(WSSMessage.self, from: jsonData),
              let b64 = wssMsg.message,
              let protoData = Data(base64Encoded: b64)
        else {
            // Try direct base64 as fallback
            if let directData = Data(base64Encoded: text),
               let ticker = try? Yaticker(serializedBytes: directData),
               ticker.quoteType != .heartbeat {
                onTick?(ticker)
            }
            return
        }

        guard let ticker = try? Yaticker(serializedBytes: protoData) else { return }
        if ticker.quoteType == .heartbeat { return }

        onTick?(ticker)
    }


    // MARK: - Heartbeat

    private func startHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: Self.heartbeatInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.subscribedSymbols.isEmpty else { return }
                self.sendJSON(["subscribe": self.subscribedSymbols])
            }
        }
    }

    // MARK: - Reconnect

    private func handleDisconnect() {
        isConnected = false
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil

        guard !subscribedSymbols.isEmpty else { return }

        let delay = min(pow(2.0, Double(reconnectAttempts)) * 2, Self.maxReconnectDelay)
        reconnectAttempts += 1
        print("[WSS] Reconnecting in \(delay)s (attempt \(reconnectAttempts))")

        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.openConnection()
            }
        }
    }
}

// MARK: - URLSessionWebSocketDelegate

extension WebSocketService: URLSessionWebSocketDelegate {
    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        Task { @MainActor in
            self.isConnected = true
            self.reconnectAttempts = 0
            self.sendJSON(["subscribe": self.subscribedSymbols])
            self.startHeartbeat()
            self.receiveMessage()
        }
    }

    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        Task { @MainActor in
            print("[WSS] Closed: \(closeCode)")
            handleDisconnect()
        }
    }
}
