// Watch app entry point and the UI model that ties workout, motion, metronome and phone link.
import AVFoundation
import Observation
import SwiftUI
import WatchKit

@main
struct CPRCoachWatchApp: App {
    @State private var model = WatchModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
        }
    }
}

@MainActor
@Observable
final class WatchModel {
    var running = false
    var phoneReachable = false
    var samplesSent = 0
    var batchesDropped = 0
    var heartRate: Int?
    var error: String?
    var bpm = 110
    var metronomeOn = true {
        didSet { syncMetronome() }
    }
    var everyOtherBeat = false {
        didSet { metronome.everyOtherBeat = everyOtherBeat }
    }
    /// Coach on the wrist: the same DSP as the phone, run on the watch, with a cue and haptics.
    var coachOnWatch = UserDefaults.standard.object(forKey: "coachOnWatch") as? Bool ?? true {
        didSet { UserDefaults.standard.set(coachOnWatch, forKey: "coachOnWatch") }
    }
    /// Speak the cues from the watch's speaker when the watch is coaching on its own (session
    /// started on the watch, or no phone). Phone-started sessions leave the talking to the phone.
    var voiceOnWatch = UserDefaults.standard.object(forKey: "voiceOnWatch") as? Bool ?? true {
        didSet { UserDefaults.standard.set(voiceOnWatch, forKey: "voiceOnWatch") }
    }
    var rate: Double?
    var depth: Double?
    var cue: WatchCue?

    @ObservationIgnored private var pipeline = WatchPipeline()
    @ObservationIgnored private var cueSince: (cue: WatchCue, t: Double)?
    @ObservationIgnored private var lastHaptic = 0.0
    @ObservationIgnored private var startedAt = 0.0
    @ObservationIgnored private var startedByPhone = false
    @ObservationIgnored private var goodSince: Double?
    @ObservationIgnored private var lastPraise = 0.0
    @ObservationIgnored private let synth = AVSpeechSynthesizer()

    @ObservationIgnored private let phone: PhoneLink
    @ObservationIgnored private let motion: MotionStreamer
    @ObservationIgnored private let workout: WorkoutManager
    @ObservationIgnored private let metronome = Metronome()

    init() {
        let (stream, events) = AsyncStream.makeStream(of: WatchEvent.self)
        phone = PhoneLink(events: events)
        motion = MotionStreamer(link: phone)
        workout = WorkoutManager(link: phone, events: events)
        motion.onPacket = { [weak self] data in
            Task { @MainActor in self?.coach(data) }
        }
        Task { [weak self] in
            for await event in stream {
                self?.apply(event)
            }
        }
        phone.activate()
    }

    func start(fromPhone: Bool = false) async {
        guard !running else { return }
        error = nil
        running = true
        startedByPhone = fromPhone
        do {
            try await workout.requestAuthorization()
            try await workout.start()
        } catch {
            // Keep streaming without the workout; it just may throttle when the screen dims.
            self.error = "Workout: \(error.localizedDescription)"
        }
        guard running else { return }
        pipeline = WatchPipeline()
        rate = nil
        depth = nil
        cue = nil
        startedAt = ProcessInfo.processInfo.systemUptime
        goodSince = nil
        lastPraise = startedAt
        if speaks {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .voicePrompt)
            try? AVAudioSession.sharedInstance().setActive(true)
            say(tr("Start compressions."))
        }
        if !motion.isAvailable { error = "Device motion unavailable" }
        motion.start()
        syncMetronome()
    }

    func stop() {
        guard running else { return }
        running = false
        synth.stopSpeaking(at: .immediate)
        motion.stop()
        workout.stop()
        syncMetronome()
    }

    // MARK: On-watch coach

    private func coach(_ data: Data) {
        guard running, let batch = CPRPacket.decode(data) else { return }
        let now = ProcessInfo.processInfo.systemUptime
        _ = pipeline.process(batch, recvTime: now)
        let age = pipeline.lastCompressionLocal.map { now - $0 }
        let fresh = (age ?? 99) < CoachConfig.watchFresh
        rate = fresh ? pipeline.rateCpm : nil
        depth = fresh ? pipeline.depthMedian : nil
        guard coachOnWatch else { cue = nil; return }
        let c = WatchCue.evaluate(rate: rate, depth: depth, lastCompressionAge: age, runningS: now - startedAt)
        cue = c
        // Praise after 10 s of good compressions, at most every 20 s.
        if c == .good {
            goodSince = goodSince ?? now
            if now - goodSince! >= 10, now - lastPraise >= 20, speaks {
                lastPraise = now
                say(tr("Great compressions, keep going."))
            }
        } else {
            goodSince = nil
        }
        // Tap the wrist (and speak) when a fault has lasted 2 s, at most every 6 s; up = more, down = less.
        guard let c, c != .good else { cueSince = nil; return }
        if cueSince?.cue != c { cueSince = (c, now) }
        if now - cueSince!.t >= 2, now - lastHaptic >= 6 {
            lastHaptic = now
            WKInterfaceDevice.current().play(c.haptic)
            if speaks { say(c.spoken) }
        }
    }

    /// The watch talks only when it's the one coaching: a session started on the watch, or no phone.
    private var speaks: Bool { voiceOnWatch && coachOnWatch && (!startedByPhone || !phoneReachable) }

    private func say(_ line: String) {
        if synth.isSpeaking { return }
        let u = AVSpeechUtterance(string: line)
        u.voice = AVSpeechSynthesisVoice(language: AppLanguage.current.locale.identifier(.bcp47))
        synth.speak(u)
    }

    private func syncMetronome() {
        if running && metronomeOn {
            if !metronome.isRunning || metronome.bpm != bpm { metronome.start(bpm: bpm) }
        } else {
            metronome.stop()
        }
    }

    private func apply(_ event: WatchEvent) {
        switch event {
        case .reachability(let r): phoneReachable = r
        case .sent(let n): samplesSent += n
        case .dropped: batchesDropped += 1
        case .heartRate(let bpm): heartRate = bpm
        case .workoutError(let msg): error = "Workout: \(msg)"
        case .command(let cmd): handle(cmd)
        }
    }

    private func handle(_ cmd: WatchCommand) {
        switch cmd {
        case .start: Task { await start(fromPhone: true) }
        case .stop: stop()
        case .metronome(let on, let newBpm):
            bpm = newBpm
            metronomeOn = on
            syncMetronome()
        }
    }
}

/// What the wrist tells the rescuer, worst first.
enum WatchCue: Equatable {
    case keepPushing, harder, faster, slower, lessForce, good

    static func evaluate(rate: Double?, depth: Double?, lastCompressionAge: Double?, runningS: Double) -> WatchCue? {
        if (lastCompressionAge ?? runningS) >= CoachConfig.noCompression + 1 { return runningS > 3 ? .keepPushing : nil }
        if let d = depth, d < Targets.depthOkMin { return .harder }
        if let r = rate, r < Targets.rateMin { return .faster }
        if let r = rate, r > Targets.rateMax { return .slower }
        if let d = depth, d > CoachConfig.tooDeepCm { return .lessForce }
        return rate == nil ? nil : .good
    }

    var text: String {
        switch self {
        case .keepPushing: tr("Keep pushing")
        case .harder: tr("Push harder")
        case .faster: tr("Faster")
        case .slower: tr("Slow down")
        case .lessForce: tr("Less force")
        case .good: tr("Good")
        }
    }

    /// The phone's spoken line for this cue (already translated in the shared table).
    var spoken: String {
        switch self {
        case .keepPushing: tr("Keep pushing! Don't stop.")
        case .harder: tr("Push harder.")
        case .faster: tr("Faster.")
        case .slower: tr("Slow down.")
        case .lessForce: tr("A little less force.")
        case .good: tr("Great compressions, keep going.")
        }
    }

    var color: Color {
        switch self {
        case .good: .green
        case .keepPushing, .harder: .red
        case .faster, .slower, .lessForce: .orange
        }
    }

    var haptic: WKHapticType {
        switch self {
        case .harder, .faster: .directionUp
        case .slower, .lessForce: .directionDown
        case .keepPushing: .retry
        case .good: .success
        }
    }
}
