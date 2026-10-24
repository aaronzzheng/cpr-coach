// Standalone phone coach: fuses the watch (processed on the phone) with the front camera's body
// pose, runs the coach rules, speaks, keeps the metronome, and scores the session.
import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class CoachModel {
    enum Phase: Equatable { case setup, countdown(Int), running, summary }

    var phase: Phase = .setup
    var live = LiveState()
    var banner: CoachRule?
    var posture: PostureFrame?
    var poseImageSize: CGSize = .zero
    var cameraStatus: CameraPose.Status = .idle
    var watchStreaming = false
    var elapsed = 0.0
    var summary: SessionSummary?
    var metronomeOn = true {
        didSet {
            if phase == .running { metronomeOn ? audio.startMetronome(bpm: Targets.rateTarget) : audio.stopMetronome() }
            sendToWatch(.metronome(on: metronomeOn, bpm: Targets.rateTarget))
        }
    }
    var muted = false { didSet { audio.muted = muted } }

    @ObservationIgnored private var pipeline = WatchPipeline(depthScale: UserDefaults.standard.object(forKey: "watchDepthScale") as? Double ?? 1.0)
    @ObservationIgnored private var tracker = PostureTracker()
    @ObservationIgnored private var cameraRate = CameraCompressionDetector()
    @ObservationIgnored private var session: SessionTracker?
    @ObservationIgnored private var engine = CoachEngine()
    @ObservationIgnored private let audio = CoachAudio()
    @ObservationIgnored private let sendToWatch: (WatchCommand) -> Void
    @ObservationIgnored private var lastPacketAt: Double?
    @ObservationIgnored private var heartRateAt: Double?
    @ObservationIgnored private var runStart = 0.0
    @ObservationIgnored private var lastCoach = 0.0
    @ObservationIgnored private(set) var camera: CameraPose!

    private var now: Double { ProcessInfo.processInfo.systemUptime }

    init(sendToWatch: @escaping (WatchCommand) -> Void) {
        self.sendToWatch = sendToWatch
        camera = CameraPose { [weak self] sample in
            Task { @MainActor in self?.handlePose(sample) }
        }
        Task { [weak self] in
            while true {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self else { return }
                self.tick()
            }
        }
    }

    func startCamera() async {
        cameraStatus = await camera.start()
    }

    // MARK: Inputs

    /// A CPR1 batch from the watch, relayed by WatchLink.
    func ingest(_ data: Data) {
        guard let batch = CPRPacket.decode(data) else { return }
        let t = now
        lastPacketAt = t
        let out = pipeline.process(batch, recvTime: t)
        guard phase == .running else { return }
        for c in out.done {
            session?.onCompression(t: c.t, instRate: c.instRateCpm, depth: c.depthCm, estimated: false, from: .watch)
        }
    }

    func heartRate(_ bpm: Int) {
        pipeline.heartRate = Double(bpm)
        heartRateAt = now
    }

    private func handlePose(_ s: PoseSample) {
        poseImageSize = s.imageSize
        let p = tracker.update(left: s.left, right: s.right, t: s.t)
        posture = p
        guard p.visible, let wrist = p.joints?.wrist else { return }
        let c = cameraRate.push(t: s.t, yPx: Double(wrist.y), frameH: Double(s.imageSize.height))
        guard phase == .running else { return }
        session?.onPosture(p)
        // The camera only grades compressions when the watch isn't streaming.
        if let c, !watchStreaming {
            let depth = c.amplitudePx.flatMap { amp in p.armLengthPx.map { amp * PoseConfig.armLengthCm / $0 } }
            session?.onCompression(t: c.t, instRate: c.instRateCpm, depth: depth, estimated: true, from: .camera)
        }
    }

    // MARK: Tick

    private func tick() {
        let t = now
        watchStreaming = lastPacketAt.map { t - $0 < 1.0 } ?? false
        var watch: WatchSnapshot?
        if watchStreaming {
            let f = pipeline.fatigue.state
            watch = WatchSnapshot(
                rateCpm: pipeline.rateCpm, depthCm: pipeline.depthMedian,
                lastCompressionAge: pipeline.lastCompressionLocal.map { t - $0 }, count: pipeline.count,
                heartRate: heartRateAt.map { t - $0 < 15 } == true ? pipeline.heartRate : nil,
                swapRecommended: f.swapRecommended, fatigueScore: f.score)
        }
        let cam = CameraSnapshot(
            on: cameraStatus == .running, lastCompressionAge: cameraRate.lastT.map { t - $0 },
            posture: posture, rateCpm: cameraRate.rateCpm, amplitudePx: cameraRate.amplitudePx, count: cameraRate.count)
        live = fuse(watch: watch, camera: cam)

        guard phase == .running else { return }
        elapsed = session?.elapsed(t) ?? 0
        if t - lastCoach >= CoachConfig.evalInterval {
            lastCoach = t
            let d = engine.evaluate(live, runningS: t - runStart, now: t)
            banner = d.banner
            if let s = d.speak { audio.say(s.line, priority: s.priority) }
        }
    }

    // MARK: Session

    func start() {
        guard phase == .setup || phase == .summary else { return }
        summary = nil
        banner = nil
        UIApplication.shared.isIdleTimerDisabled = true
        sendToWatch(.start)
        audio.say("Get ready.", priority: 0)
        Task {
            for n in stride(from: CoachConfig.countdown, through: 1, by: -1) {
                phase = .countdown(n)
                try? await Task.sleep(for: .seconds(1))
                if case .setup = phase { return } // cancelled
            }
            runStart = now
            session = SessionTracker(startedAt: runStart)
            engine.reset()
            pipeline.swap()
            cameraRate = CameraCompressionDetector()
            if metronomeOn { audio.startMetronome(bpm: Targets.rateTarget) }
            sendToWatch(.metronome(on: metronomeOn, bpm: Targets.rateTarget))
            audio.say("Start compressions.", priority: 0)
            phase = .running
        }
    }

    func stop() {
        audio.stopMetronome()
        UIApplication.shared.isIdleTimerDisabled = false
        if case .countdown = phase {
            phase = .setup
            return
        }
        guard phase == .running else { return }
        summary = session?.finish(now)
        session = nil
        banner = nil
        audio.say("Stop. Well done.", priority: 0)
        phase = .summary
    }

    func swapRescuers() { pipeline.swap() }

    func backToSetup() { phase = .setup }
}
