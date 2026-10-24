// 100 Hz deviceMotion on a background queue, batched 20 samples (200 ms) per CPR1 packet and
// handed to PhoneLink. Batches are dropped, not queued, when the phone isn't reachable.
import CoreMotion
import Foundation

nonisolated final class MotionStreamer: @unchecked Sendable {
    static let sampleHz = 100.0
    static let batchSize = 20

    private let manager = CMMotionManager()
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.name = "cpr.motion"
        q.maxConcurrentOperationCount = 1
        q.qualityOfService = .userInteractive
        return q
    }()
    private let link: PhoneLink

    // Confined to `queue`.
    private var encoder = CPRPacketEncoder()
    private var seq: UInt32 = 0

    init(link: PhoneLink) {
        self.link = link
    }

    var isAvailable: Bool { manager.isDeviceMotionAvailable }

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        queue.addOperation { [self] in encoder.reset() }
        manager.deviceMotionUpdateInterval = 1.0 / Self.sampleHz
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: queue) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.append(motion)
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }

    private func append(_ m: CMDeviceMotion) {
        let ua = m.userAcceleration
        let g = m.gravity
        let rr = m.rotationRate
        encoder.append(
            ts: m.timestamp,
            values: [ua.x, ua.y, ua.z, g.x, g.y, g.z, rr.x, rr.y, rr.z].map { Float32($0) }
        )
        guard encoder.count == Self.batchSize else { return }
        let packet = encoder.flush(seq: seq)
        seq &+= 1  // increments even when dropped, so the backend sees the gap
        link.sendIMU(packet, samples: Self.batchSize)
    }
}
