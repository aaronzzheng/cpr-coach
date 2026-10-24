// WatchConnectivity on the watch side: sends IMU batches and heart rate to the iPhone relay,
// and receives start/stop/metronome commands from it.
import Foundation
import WatchConnectivity

/// Commands the laptop (via the phone) can send to the watch.
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
}

/// Everything background callbacks report to the UI model, delivered in order.
nonisolated enum WatchEvent: Sendable {
    case reachability(Bool)
    case command(WatchCommand)
    case sent(samples: Int)
    case dropped
    case heartRate(Int)
    case workoutError(String)
}

nonisolated final class PhoneLink: NSObject, WCSessionDelegate, @unchecked Sendable {
    private let events: AsyncStream<WatchEvent>.Continuation

    init(events: AsyncStream<WatchEvent>.Continuation) {
        self.events = events
        super.init()
    }

    private var session: WCSession { WCSession.default }

    func activate() {
        guard WCSession.isSupported() else { return }
        session.delegate = self
        session.activate()
    }

    private var canSend: Bool {
        session.activationState == .activated && session.isReachable
    }

    func sendIMU(_ packet: Data, samples: Int) {
        guard canSend else {
            events.yield(.dropped)
            return
        }
        session.sendMessageData(packet, replyHandler: nil) { [events] _ in
            events.yield(.dropped)
        }
        events.yield(.sent(samples: samples))
    }

    /// `ts` is seconds since boot, the same clock as CMDeviceMotion.timestamp.
    func sendHeartRate(bpm: Int, ts: Double) {
        guard canSend else { return }
        session.sendMessage(["t": "hr", "bpm": bpm, "ts": ts], replyHandler: nil, errorHandler: nil)
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: (any Error)?) {
        events.yield(.reachability(session.isReachable))
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        events.yield(.reachability(session.isReachable))
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if let cmd = WatchCommand(dictionary: message) { events.yield(.command(cmd)) }
    }

    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        if let cmd = WatchCommand(dictionary: message) { events.yield(.command(cmd)) }
        replyHandler([:])
    }
}
