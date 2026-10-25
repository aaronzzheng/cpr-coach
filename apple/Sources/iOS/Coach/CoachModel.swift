// Standalone phone coach: fuses the watch (processed on the phone) with the front camera's body
// pose, runs the coach rules, speaks, keeps the metronome, and scores the session.
import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class CoachModel {
    enum Phase: Equatable { case setup, countdown(Int), running, summary }
    enum Mode: Equatable { case training, emergency, skillsCheck }
    /// The spoken emergency check before compressions: responsive? breathing normally?
    enum TriageStep: Equatable { case responsive, breathing, monitor, recovery }

    var phase: Phase = .setup
    var mode: Mode = .training
    var live = LiveState()
    var banner: CoachRule?
    var posture: PostureFrame?
    var poseImageSize: CGSize = .zero
    var cameraStatus: CameraPose.Status = .idle
    var watchStreaming = false
    var elapsed = 0.0
    var summary: SessionSummary?
    var debrief: Debrief?
    /// When the demo emergency call started; nil when no call is showing.
    var simulatedCallSince: Date?
    var metronomeOn = true {
        didSet {
            if phase == .running { metronomeOn ? audio.startMetronome(bpm: Targets.rateTarget) : audio.stopMetronome() }
            sendToWatch(.metronome(on: metronomeOn, bpm: Targets.rateTarget))
        }
    }
    var muted = false { didSet { audio.muted = muted } }
    var language = AppLanguage.current {
        didSet {
            AppLanguage.set(language)
            updateListening(restart: true)
        }
    }
    /// Voice commands on (default) — the rescuer's hands are busy.
    var handsFree = UserDefaults.standard.object(forKey: "handsFree") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(handsFree, forKey: "handsFree")
            updateListening()
        }
    }
    var listening = false
    /// The last command understood, shown briefly so the rescuer knows they were heard.
    var heard: String?
    var triage: TriageStep?
    /// Recorded watch session playing in place of the live watch (stage backup).
    var demoReplay = false
    /// Bumped on every long press, for a haptic each time.
    var demoReplayStep = 0
    /// Who is being resuscitated; sets the depth targets.
    var patient: PatientProfile = .adult { didSet { PatientProfile.current = patient } }
    /// 30 compressions then 2 rescue breaths, for trained rescuers (off = hands-only CPR).
    var breathsMode = UserDefaults.standard.bool(forKey: "breathsMode") {
        didSet { UserDefaults.standard.set(breathsMode, forKey: "breathsMode") }
    }
    /// Compressions so far in the current 30:2 cycle.
    var cycleCount = 0
    /// What happened when, for the paramedic handoff.
    var events: [TimelineEvent] = []
    var showAEDGuide = false
    /// The emergency screen (from the setup card, Siri or the Action button).
    var showEmergency = false
    var swaps = 0
    var triageAwaitingAnswer: Bool { triage == .responsive || triage == .breathing }

    @ObservationIgnored private var pipeline = WatchPipeline(depthScale: UserDefaults.standard.object(forKey: "watchDepthScale") as? Double ?? 1.0)
    @ObservationIgnored private var tracker = PostureTracker()
    @ObservationIgnored private var cameraRate = CameraCompressionDetector()
    @ObservationIgnored private var fusion = DepthFusion()
    @ObservationIgnored private var fusedDepths: [Double] = []
    @ObservationIgnored private var recoil = RecoilTracker()
    @ObservationIgnored private var hands = HandPlacementTracker()
    @ObservationIgnored private var session: SessionTracker?
    @ObservationIgnored private var engine = CoachEngine()
    @ObservationIgnored private let audio = CoachAudio()
    @ObservationIgnored private let listener = VoiceListener()
    @ObservationIgnored private var heardClear: Task<Void, Never>?
    @ObservationIgnored private let replay = DemoReplay()
    @ObservationIgnored private var forecaster = SwapForecaster()
    @ObservationIgnored private var breathSince: Double?
    @ObservationIgnored private var cyclesAnnounced = 0
    @ObservationIgnored private let liveActivity = LiveActivityController()

    /// The running coach, for Siri/Shortcuts intents; if the app is still launching, the request waits.
    private static weak var shared: CoachModel?
    private static var pending: (() -> Void)?

    static func requestEmergency() {
        let go = { (m: CoachModel) in if m.phase == .setup || m.phase == .summary { m.phase = .setup; m.showEmergency = true } }
        if let m = shared { go(m) } else { pending = { if let m = shared { go(m) } } }
    }

    static func requestPractice() {
        let go = { (m: CoachModel) in if m.phase == .setup || m.phase == .summary { m.start() } }
        if let m = shared { go(m) } else { pending = { if let m = shared { go(m) } } }
    }
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
        Self.shared = self
        if let p = Self.pending {
            Self.pending = nil
            Task { @MainActor in p() }
        }
        listener.onPhrase = { [weak self] text in self?.handlePhrase(text) ?? false }
        listener.echoLine = { [weak self] in self?.audio.echoLine }
        audio.onSpeechEnd = { [weak self] in self?.listener.coachFinished() }
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
    func ingest(_ data: Data, replayed: Bool = false) {
        if replay.running && !replayed { return } // the recording owns the watch stream while it plays
        guard let batch = CPRPacket.decode(data) else { return }
        let t = now
        lastPacketAt = t
        let out = pipeline.process(batch, recvTime: t)
        for s in pipeline.lastSamples { fusion.pushIMU(at: s.t, aUp: s.aUp) }
        var done = out.done
        if fusion.converged {
            // Swap the watch-only depth (double integration) for the drift-free fused depth.
            for i in done.indices {
                let half = 0.5 * (done[i].intervalS ?? 0.55)
                guard let d = fusion.depthCm(from: done[i].t - half, to: done[i].t + half) else { continue }
                done[i].depthCm = d
                fusedDepths.append(d)
                if fusedDepths.count > DSPConfig.depthWindow { fusedDepths.removeFirst() }
            }
        }
        guard phase == .running else { return }
        for b in out.bottoms { onBottom(b.t) }
        for c in done {
            session?.onCompression(t: c.t, instRate: c.instRateCpm, depth: c.depthCm, estimated: false, from: .watch)
            if let d = c.depthCm { forecaster.push(t: c.t, depth: d) }
        }
    }

    /// Long-press on the watch status: off → recorded real session → tiring rescuer → off.
    func toggleDemoReplay() {
        let deliver: @MainActor (Data) -> Void = { [weak self] data in self?.ingest(data, replayed: true) }
        switch replay.session {
        case nil: replay.start(.good, deliver: deliver)
        case .good?: replay.start(.fatigue, deliver: deliver)
        case .fatigue?: replay.stop()
        }
        demoReplay = replay.running
        demoReplayStep += 1
    }

    func heartRate(_ bpm: Int) {
        pipeline.heartRate = Double(bpm)
        heartRateAt = now
    }

    private func handlePose(_ s: PoseSample) {
        poseImageSize = s.imageSize
        let p = tracker.update(left: s.left, right: s.right, t: s.t, elbow3DLeft: s.elbow3DLeft, elbow3DRight: s.elbow3DRight)
        posture = p
        hands.update(t: s.t, wrist: p.visible ? p.joints?.wrist : nil, torso: s.patientTorso)
        guard p.visible, let wrist = p.joints?.wrist else { return }
        if watchStreaming, let arm = p.armLengthPx, arm > 0 {
            fusion.pushCamera(t: s.t, y: Double(wrist.y), pixelsPerMetreGuess: arm / (PoseConfig.armLengthCm / 100))
        }
        let c = cameraRate.push(t: s.t, yPx: Double(wrist.y), frameH: Double(s.imageSize.height))
        guard phase == .running else { return }
        session?.onPosture(p)
        if let c, let top = c.topY, let k = fusedCmPerPx ?? p.armLengthPx.map({ PoseConfig.armLengthCm / $0 }) {
            recoil.push(t: c.t, topY: top, cmPerPx: k)
            session?.recoilPct = recoil.fullPct
        }
        // The camera only grades compressions when the watch isn't streaming.
        if let c, !watchStreaming { onBottom(c.t) }
        if let c, !watchStreaming {
            if let k = fusedCmPerPx {
                session?.onCompression(t: c.t, instRate: c.instRateCpm, depth: c.amplitudePx.map { $0 * k }, estimated: false, from: .camera)
            } else {
                let depth = c.amplitudePx.flatMap { amp in p.armLengthPx.map { amp * PoseConfig.armLengthCm / $0 } }
                session?.onCompression(t: c.t, instRate: c.instRateCpm, depth: depth, estimated: true, from: .camera)
            }
        }
    }

    /// Camera centimetres per pixel, once the filter has learned it from the watch.
    private var fusedCmPerPx: Double? {
        fusion.converged && fusion.pixelsPerCm > 0 ? 1 / fusion.pixelsPerCm : nil
    }

    // MARK: Rescue breaths (30:2)

    /// Every compression bottom, from whichever source leads.
    private func onBottom(_ t: Double) {
        if let since = breathSince {
            guard t - since >= BreathConfig.resumeAfterS else { return }
            endBreaths(prompt: false) // compressions resumed on their own
        }
        cycleCount += 1
        if breathsMode && cycleCount >= BreathConfig.compressions { beginBreaths() }
    }

    private func beginBreaths() {
        breathSince = now
        cycleCount = 0
        session?.plannedPause = true
        audio.stopMetronome()
        audio.say(tr("Give 2 breaths."), priority: 0)
        engine.markSpoken("breaths", now: now)
    }

    func endBreaths(prompt: Bool) {
        guard breathSince != nil else { return }
        breathSince = nil
        if metronomeOn && phase == .running { audio.startMetronome(bpm: Targets.rateTarget) }
        if prompt { audio.say(tr("Resume compressions now."), priority: 0) }
    }

    // MARK: Tick

    private func tick() {
        let t = now
        watchStreaming = lastPacketAt.map { t - $0 < 1.0 } ?? false
        var watch: WatchSnapshot?
        if watchStreaming {
            let f = pipeline.fatigue.state
            let fused = fusion.converged ? median(fusedDepths) : nil
            watch = WatchSnapshot(
                rateCpm: pipeline.rateCpm, depthCm: fused ?? pipeline.depthMedian, depthFused: fused != nil,
                lastCompressionAge: pipeline.lastCompressionLocal.map { t - $0 }, count: pipeline.count,
                heartRate: heartRateAt.map { t - $0 < 15 } == true ? pipeline.heartRate : nil,
                swapRecommended: f.swapRecommended, fatigueScore: f.score)
        }
        let cam = CameraSnapshot(
            on: cameraStatus == .running, lastCompressionAge: cameraRate.lastT.map { t - $0 },
            posture: posture, rateCpm: cameraRate.rateCpm, amplitudePx: cameraRate.amplitudePx, count: cameraRate.count,
            fusedCmPerPx: fusedCmPerPx)
        live = fuse(watch: watch, camera: cam)
        live.recoilIncomplete = phase == .running && recoil.incomplete && (live.lastCompressionAge ?? 99) < CoachConfig.stale
        if let since = breathSince, t - since > BreathConfig.maxPauseS { endBreaths(prompt: true) }
        live.breathPause = breathSince != nil
        live.handPlacement = phase == .running ? hands.issue : nil
        live.swapInS = phase == .running && watchStreaming ? forecaster.update(now: t, limit: Targets.depthMin) : nil

        guard phase == .running else { return }
        elapsed = session?.elapsed(t) ?? 0
        let rule = banner
        liveActivity.update(rate: live.rateCpm, depth: coachableDepth(live) ?? live.depthCm,
                            instruction: rule.map { tr($0.banner) } ?? tr("Keep going"), tone: rule?.tone ?? .good)
        if mode == .skillsCheck && elapsed >= SkillsCheck.durationS {
            stop()
            return
        }
        // Every 2 minutes in a real emergency: swap, and let the AED analyze.
        if mode == .emergency, Int(elapsed / Targets.rescuerSwap) > cyclesAnnounced {
            cyclesAnnounced = Int(elapsed / Targets.rescuerSwap)
            audio.say(aedArrivedAt == nil
                      ? tr("Two minutes. Switch rescuers if someone can take over. Don't stop.")
                      : tr("Two minutes. Let the AED analyze: everyone stand clear, don't touch them. Then switch rescuers."), priority: 0)
            engine.markSpoken("swap", now: t)
        }
        if t - lastCoach >= CoachConfig.evalInterval {
            lastCoach = t
            let d = engine.evaluate(live, runningS: t - runStart, now: t)
            banner = d.banner
            if let s = d.speak { audio.say(tr(s.line), priority: s.priority) }
        }
    }

    // MARK: Session

    func start(skillsCheck: Bool = false) {
        guard phase == .setup || phase == .summary else { return }
        mode = skillsCheck ? .skillsCheck : .training
        prepare()
        audio.say(tr("Get ready."), priority: 0)
        Task {
            for n in stride(from: CoachConfig.countdown, through: 1, by: -1) {
                phase = .countdown(n)
                try? await Task.sleep(for: .seconds(1))
                if case .setup = phase { return } // cancelled
            }
            beginRunning(voice: tr("Start compressions."))
        }
    }

    /// Real emergency: no countdown, voice and metronome forced on, plain-language first instruction.
    func startEmergency(voice: String? = nil) {
        guard phase == .setup || phase == .summary else { return }
        mode = .emergency
        triage = nil
        log(.compressions)
        muted = false
        metronomeOn = true
        prepare()
        beginRunning(voice: voice ?? tr("Push hard and fast in the center of the chest. Follow the beat. Don't stop."))
    }

    // MARK: Emergency check (spoken, answered by voice or buttons)

    func beginTriage() {
        if phase != .running { events = [] }
        log(.check)
        triage = .responsive
        audio.say(tr("Tap their shoulders and shout. Are they responding? Say yes or no."), priority: 0)
        updateListening()
    }

    func answerTriage(_ yes: Bool) {
        switch triage {
        case .responsive:
            if yes {
                triage = .monitor
                audio.say(tr("Stay with them and call for help if they get worse. Keep checking their breathing."), priority: 0)
            } else {
                triage = .breathing
                audio.say(tr("Look at their chest for up to ten seconds. Are they breathing normally? Gasping doesn't count. Say yes or no."), priority: 0)
            }
        case .breathing:
            if yes {
                triage = .recovery
                audio.say(tr("Roll them onto their side and call for help. Keep checking their breathing."), priority: 0)
            } else {
                // Not breathing normally: get help coming and start CPR, in one step.
                if simulatedCallSince == nil {
                    simulatedCallSince = Date()
                    log(.call)
                }
                startEmergency(voice: tr("No normal breathing. Calling for help. Start compressions now: push hard and fast in the center of the chest and follow the beat."))
            }
        default:
            break
        }
        updateListening()
    }

    func endTriage() {
        triage = nil
        updateListening()
    }

    // MARK: Voice commands

    private func updateListening(restart: Bool = false) {
        let want = handsFree && (phase == .running || triage != nil)
        if want && (restart || !listening) {
            listening = true
            Task {
                await listener.start(language: language)
                listening = listener.state == .listening
            }
        } else if !want && listening {
            listener.stop()
            listening = false
        }
    }

    /// New words from the listener; returns true if they were a command.
    private func handlePhrase(_ text: String) -> Bool {
        guard let cmd = CommandMatcher.match(text, lang: language, expectingAnswer: triageAwaitingAnswer, expectingDone: breathSince != nil) else { return false }
        let running = phase == .running
        switch cmd {
        case .yes, .no:
            guard triageAwaitingAnswer else { return false }
            showHeard(cmd == .yes ? tr("Yes") : tr("No"))
            answerTriage(cmd == .yes)
        case .stop:
            guard running else { return false }
            showHeard(tr("Stop"))
            stop()
        case .swap:
            guard running else { return false }
            showHeard(tr("Swap"))
            swapRescuers()
            audio.say(tr("Switch now. Next rescuer, start compressions."), priority: 0, interrupt: true)
        case .time:
            guard running else { return false }
            showHeard(tr("How long"))
            let t = Int(elapsed)
            let n = "\(live.count)"
            audio.say(t >= 60 ? tr("%@ minutes %@ seconds, %@ compressions.", "\(t / 60)", "\(t % 60)", n)
                              : tr("%@ seconds, %@ compressions.", "\(t)", n), priority: 0, interrupt: true)
        case .status:
            guard running else { return false }
            showHeard(tr("How am I doing"))
            audio.say(statusLine(), priority: 0, interrupt: true)
        case .call:
            showHeard(tr("Call for help"))
            callEmergency()
        case .done:
            guard breathSince != nil else { return false }
            showHeard(tr("Done"))
            endBreaths(prompt: true)
        }
        return true
    }

    private func showHeard(_ s: String) {
        heard = s
        heardClear?.cancel()
        heardClear = Task {
            try? await Task.sleep(for: .seconds(2.5))
            if !Task.isCancelled { heard = nil }
        }
    }

    /// A spoken one-breath status: the numbers, then the fix (or praise).
    private func statusLine() -> String {
        var parts: [String] = []
        if let r = live.rateCpm { parts.append(tr("Rate %@.", "\(Int(r.rounded()))")) }
        if let d = coachableDepth(live) { parts.append(tr("Depth %@ centimeters.", trNumber(d, digits: 1))) }
        if parts.isEmpty { return tr("I can't see compressions yet. Push hard and fast.") }
        if let b = banner, b.id != "praise" { parts.append(tr(b.line)) } else { parts.append(tr("Looking good, keep going.")) }
        return parts.joined(separator: " ")
    }

    /// Hackathon build: never dial. Shows a demo call banner and says what would happen instead.
    func callEmergency() {
        guard simulatedCallSince == nil else { return }
        simulatedCallSince = Date()
        log(.call)
        audio.say(tr("Demo call. In a real emergency, this would call %@.", Self.emergencyNumber), priority: 0)
    }

    func endSimulatedCall() { simulatedCallSince = nil }

    // MARK: AED and handoff

    var aedArrivedAt: Date? { events.first { $0.kind == .aed }?.at }

    func aedArrived() {
        if aedArrivedAt == nil { log(.aed) }
        showAEDGuide = true
        audio.say(tr("Turn the AED on and follow its voice. Keep pushing while someone attaches the pads."), priority: 0)
    }

    private func log(_ kind: TimelineEvent.Kind) {
        events.append(TimelineEvent(at: Date(), kind: kind))
    }

    /// Everything a paramedic asks on arrival, from this session.
    var handoff: HandoffReport? {
        guard let s = summary else { return nil }
        return HandoffReport(events: events, summary: s, swaps: swaps, patient: patient)
    }

    /// The local emergency number for the phone's region.
    static var emergencyNumber: String {
        switch Locale.current.region?.identifier {
        case "US", "CA", "MX", "PR": "911"
        case "GB", "IE": "999"
        case "AU": "000"
        case "NZ": "111"
        case "JP", "KR", "TW": "119"
        case "CN": "120"
        default: "112"
        }
    }

    private func prepare() {
        summary = nil
        debrief = nil
        banner = nil
        UIApplication.shared.isIdleTimerDisabled = true
        sendToWatch(.start)
    }

    private func beginRunning(voice: String) {
        runStart = now
        session = SessionTracker(startedAt: runStart)
        engine.reset()
        cyclesAnnounced = 0
        swaps = 0
        pipeline.swap()
        fusedDepths.removeAll()
        recoil.reset()
        forecaster.reset()
        breathSince = nil
        cycleCount = 0
        cameraRate = CameraCompressionDetector()
        if metronomeOn { audio.startMetronome(bpm: Targets.rateTarget) }
        sendToWatch(.metronome(on: metronomeOn, bpm: Targets.rateTarget))
        audio.say(voice, priority: 0)
        liveActivity.start(emergency: mode == .emergency)
        phase = .running
        updateListening()
    }

    func stop() {
        breathSince = nil
        audio.stopMetronome()
        UIApplication.shared.isIdleTimerDisabled = false
        if case .countdown = phase {
            phase = .setup
            return
        }
        guard phase == .running else { return }
        liveActivity.end()
        summary = session?.finish(now)
        session = nil
        if mode != .emergency, let s = summary {
            Task { debrief = await makeDebrief(s, language: language) }
        }
        banner = nil
        if mode == .emergency { log(.stopped) }
        audio.say(mode == .emergency ? tr("Stopped.") : tr("Stop. Well done."), priority: 0, interrupt: true)
        phase = .summary
        updateListening()
    }

    func swapRescuers() {
        if phase == .running {
            swaps += 1
            log(.swap)
        }
        pipeline.swap()
        recoil.reset() // a new rescuer's hands sit at a different height
        forecaster.reset()
        fusedDepths.removeAll() // new rescuer, new depth; the learned camera scale still holds
    }

    func backToSetup() { phase = .setup }
}
