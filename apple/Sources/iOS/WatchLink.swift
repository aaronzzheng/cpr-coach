// WatchConnectivity on the phone: forwards IMU batches (binary) and heart rate (JSON text)
// to the laptop in arrival order, and relays laptop commands to the watch.
import Foundation
import WatchConnectivity

/// Commands the laptop can send to the watch (same wire format on both hops).
nonisolated enum WatchCommand: Sendable, Equatable {
    case start
    case stop
    case metronome(on: Bool, bpm: Int)

    init?(dictionary d: [String: Any]) {
        switch d["cmd"] as? String {
        case "start": self = .start
        case "stop": self = .stop
        case "metronome": self = .metronome(on: d["on"] as? Bool ?? true, bpm: d["bpm"] as? Int ?? 110)
        default: return nil
        }
    }

    init?(json: String) {
        guard let data = json.data(using: .utf8),
              let d = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        self.init(dictionary: d)
    }

    var dictionary: [String: Any] {
        switch self {
        case .start: ["cmd": "start"]
        case .stop: ["cmd": "stop"]
        case .metronome(let on, let bpm): ["cmd": "metronome", "on": on, "bpm": bpm]
        }
    }
}

/// A frame bound for the laptop.
nonisolated enum Outbound: Sendable {
    case imu(Data)
    case text(String)
}

/// Everything background callbacks report to the UI model.
nonisolated enum RelayEvent: Sendable {
    case watchState(paired: Bool, installed: Bool, reachable: Bool)
    case imuIn
    case heartRate(Int)
    case socket(LaptopSocket.State)
    case socketError(String)
    case sent
    case dropped
    case command(WatchCommand)
}

nonisolated func jsonString(_ object: [String: Any]) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: object) else { return "{}" }
    return String(decoding: data, as: UTF8.self)
}

nonisolated final class WatchLink: NSObject, WCSessionDelegate, @unchecked Sendable {
    private let events: AsyncStream<RelayEvent>.Continuation
    private let outbound: AsyncStream<Outbound>.Continuation

    init(events: AsyncStream<RelayEvent>.Continuation, outbound: AsyncStream<Outbound>.Continuation) {
        self.events = events
        self.outbound = outbound
        super.init()
    }

    private var session: WCSession { WCSession.default }

    func activate() {
        guard WCSession.isSupported() else { return }
        session.delegate = self
        session.activate()
    }

    var isReachable: Bool { session.isReachable }

    func send(_ cmd: WatchCommand) {
        guard session.activationState == .activated, session.isReachable else { return }
        session.sendMessage(cmd.dictionary, replyHandler: nil, errorHandler: nil)
    }

    private func publishState(_ s: WCSession) {
        events.yield(.watchState(paired: s.isPaired, installed: s.isWatchAppInstalled, reachable: s.isReachable))
    }

    private func handle(_ message: [String: Any]) {
        guard message["t"] as? String == "hr", let bpm = message["bpm"] as? Int else { return }
        let ts = message["ts"] as? Double ?? 0
        outbound.yield(.text(jsonString([
            "t": "hr", "bpm": bpm, "ts": ts, "phone_rx": Date().timeIntervalSince1970,
        ])))
        events.yield(.heartRate(bpm))
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: (any Error)?) {
        publishState(session)
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // Happens when switching paired watches; reactivate for the new one.
        session.activate()
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        publishState(session)
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        publishState(session)
    }

    func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        outbound.yield(.imu(messageData))
        events.yield(.imuIn)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handle(message)
    }

    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        handle(message)
        replyHandler([:])
    }
}
