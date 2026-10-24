// WebSocket to the laptop's /ingest: hello on connect, binary IMU frames (0x01 + packet),
// text frames for heart rate/status, ping every 5 s, auto-reconnect with backoff.
import Foundation

actor LaptopSocket {
    nonisolated enum State: Sendable, Equatable {
        case disconnected
        case connecting
        case connected

        var label: String {
            switch self {
            case .disconnected: "disconnected"
            case .connecting: "connecting…"
            case .connected: "connected"
            }
        }
    }

    static let imuFrameType: UInt8 = 0x01
    static let backoff: [Double] = [0.5, 1, 2, 4]
    static let pingInterval: Duration = .seconds(5)

    private let events: AsyncStream<RelayEvent>.Continuation
    private var task: URLSessionWebSocketTask?
    private var url: URL?
    private var wanted = false
    private var attempt = 0
    /// Bumped on every (re)connect so stale loops from an old socket exit quietly.
    private var generation = 0
    private(set) var state: State = .disconnected

    init(events: AsyncStream<RelayEvent>.Continuation) {
        self.events = events
    }

    func connect(to url: URL) {
        self.url = url
        wanted = true
        attempt = 0
        open()
    }

    func disconnect() {
        wanted = false
        generation += 1
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        setState(.disconnected)
    }

    /// Sends one frame. Frames are dropped (not queued) while disconnected.
    func send(_ frame: Outbound) async {
        guard state == .connected, let task else {
            events.yield(.dropped)
            return
        }
        let message: URLSessionWebSocketTask.Message
        switch frame {
        case .imu(let packet):
            var data = Data([Self.imuFrameType])
            data.append(packet)
            message = .data(data)
        case .text(let text):
            message = .string(text)
        }
        do {
            try await task.send(message)
            events.yield(.sent)
        } catch {
            events.yield(.dropped)
            await failed(generation)
        }
    }

    private func setState(_ s: State) {
        state = s
        events.yield(.socket(s))
    }

    private func open() {
        guard wanted, let url else { return }
        generation += 1
        let gen = generation
        task?.cancel()
        let t = URLSession.shared.webSocketTask(with: url)
        task = t
        setState(.connecting)
        t.resume()
        Task { await run(t, gen) }
    }

    private func run(_ t: URLSessionWebSocketTask, _ gen: Int) async {
        do {
            // The first send completes only once the handshake has succeeded.
            try await t.send(.string(jsonString(["t": "hello", "device": "iphone", "app_version": "0.1"])))
            guard gen == generation else { return }
            attempt = 0
            setState(.connected)
            Task { await pingLoop(t, gen) }
            while gen == generation {
                if case .string(let text) = try await t.receive(), let cmd = WatchCommand(json: text) {
                    events.yield(.command(cmd))
                }
            }
        } catch {
            await failed(gen)
        }
    }

    private func pingLoop(_ t: URLSessionWebSocketTask, _ gen: Int) async {
        while gen == generation {
            try? await Task.sleep(for: Self.pingInterval)
            guard gen == generation else { return }
            t.sendPing { _ in }
        }
    }

    private func failed(_ gen: Int) async {
        guard gen == generation, wanted else { return }
        generation += 1
        let retryGen = generation
        task?.cancel()
        task = nil
        setState(.connecting)
        let delay = Self.backoff[min(attempt, Self.backoff.count - 1)]
        attempt += 1
        try? await Task.sleep(for: .seconds(delay))
        guard retryGen == generation, wanted else { return }
        open()
    }
}
