// Stage backup: plays a real recorded watch session into the coach as if the watch were live, at
// the original timing, looping. Turned on with a long press on the "Watch" status in the top bar,
// for when Bluetooth drops in front of the judges. The camera stays live.
import Foundation

@MainActor
final class DemoReplay {
    private(set) var running = false
    private var task: Task<Void, Never>?

    /// (seconds since the first packet, CPR1 packet) from the bundled recording.
    private static let packets: [(Double, Data)] = {
        guard let url = Bundle.main.url(forResource: "demo-session", withExtension: "jsonl"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var out: [(Double, Data)] = []
        for line in text.split(separator: "\n") {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  obj["k"] as? String == "imu", let rx = obj["rx"] as? Double,
                  let b64 = obj["b64"] as? String, let data = Data(base64Encoded: b64) else { continue }
            out.append((rx, data))
        }
        guard let t0 = out.first?.0 else { return [] }
        return out.map { ($0.0 - t0, $0.1) }
    }()

    static var available: Bool { !packets.isEmpty }

    func start(_ deliver: @escaping @MainActor (Data) -> Void) {
        stop()
        let packets = Self.packets
        guard !packets.isEmpty else { return }
        running = true
        task = Task { @MainActor in
            while !Task.isCancelled {
                let start = ContinuousClock.now
                for (t, data) in packets {
                    try? await Task.sleep(until: start + .seconds(t), clock: .continuous)
                    if Task.isCancelled { return }
                    deliver(data)
                }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        running = false
    }
}
