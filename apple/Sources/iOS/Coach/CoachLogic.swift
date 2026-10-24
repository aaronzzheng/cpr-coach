// On-phone coaching logic — Swift ports of web/src (postureMetrics, cameraCompressions, fuse,
// coach rules/engine, sessionTracker) and backend/app/session.py (scoring).
// Pure Foundation/CoreGraphics so it can be unit-tested on the Mac.
import CoreGraphics
import Foundation

// MARK: Posture

nonisolated enum Side { case left, right }

/// One arm's joints in image pixels (origin top-left) with Vision confidences.
nonisolated struct ArmJoints {
    var shoulder: CGPoint, elbow: CGPoint, wrist: CGPoint
    var confidence: Float // weakest of the three
}

nonisolated struct PostureFrame {
    var t: Double
    var side: Side
    var visible: Bool
    var joints: ArmJoints?
    var elbowAngleDeg: Double?
    var alignAngleDeg: Double?
    var elbowsLocked: Bool?
    var aligned: Bool?
    var elbowViolationFrac = 0.0
    var alignViolationFrac = 0.0
    var armLengthPx: Double?
}

nonisolated func angleDeg(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Double {
    let v1 = (Double(a.x - b.x), Double(a.y - b.y)), v2 = (Double(c.x - b.x), Double(c.y - b.y))
    let n = hypot(v1.0, v1.1) * hypot(v2.0, v2.1)
    guard n > 0 else { return 0 }
    return acos(min(1, max(-1, (v1.0 * v2.0 + v1.1 * v2.1) / n))) * 180 / .pi
}

/// Angle of the shoulder→wrist vector from straight down (image y grows downward).
nonisolated func fromVerticalDeg(_ shoulder: CGPoint, _ wrist: CGPoint) -> Double {
    atan2(abs(Double(wrist.x - shoulder.x)), Double(wrist.y - shoulder.y)) * 180 / .pi
}

nonisolated struct PostureTracker {
    private var side: Side = .left
    private var elbowEma: Double?
    private var bentSince: Double?
    private var misalignedSince: Double?
    private var window: [(t: Double, elbow: Bool, align: Bool)] = []
    private var armLengths: [Double] = []

    mutating func update(left: ArmJoints?, right: ArmJoints?, t: Double) -> PostureFrame {
        window.removeAll { t - $0.t > PoseConfig.postureWindow }
        let current = side == .left ? left : right
        let other = side == .left ? right : left
        if let o = other, o.confidence > (current?.confidence ?? 0) + PoseConfig.sideSwitchMargin {
            side = side == .left ? .right : .left
            elbowEma = nil
        }
        guard let arm = side == .left ? left : right, arm.confidence >= PoseConfig.minConfidence else {
            elbowEma = nil; bentSince = nil; misalignedSince = nil
            return frame(t: t, visible: false, joints: nil, elbow: nil, align: nil)
        }
        let raw = angleDeg(arm.shoulder, arm.elbow, arm.wrist)
        elbowEma = elbowEma.map { PoseConfig.elbowEmaAlpha * raw + (1 - PoseConfig.elbowEmaAlpha) * $0 } ?? raw
        armLengths.append(hypot(Double(arm.wrist.x - arm.shoulder.x), Double(arm.wrist.y - arm.shoulder.y)))
        if armLengths.count > PoseConfig.armLengthSamples { armLengths.removeFirst() }
        return frame(t: t, visible: true, joints: arm, elbow: elbowEma, align: fromVerticalDeg(arm.shoulder, arm.wrist))
    }

    private mutating func frame(t: Double, visible: Bool, joints: ArmJoints?, elbow: Double?, align: Double?) -> PostureFrame {
        let locked = elbow.map { $0 >= Targets.elbowLockedMinDeg }
        let aligned = align.map { $0 <= Targets.shoulderOverHandsMaxDeg }
        bentSince = locked == false ? (bentSince ?? t) : nil
        misalignedSince = aligned == false ? (misalignedSince ?? t) : nil
        let elbowViolation = bentSince.map { t - $0 >= PoseConfig.violationHold } ?? false
        let alignViolation = misalignedSince.map { t - $0 >= PoseConfig.violationHold } ?? false
        if visible { window.append((t, elbowViolation, alignViolation)) }
        let n = Double(window.count)
        var f = PostureFrame(t: t, side: side, visible: visible, joints: joints, elbowAngleDeg: elbow, alignAngleDeg: align,
                             elbowsLocked: locked, aligned: aligned)
        f.elbowViolationFrac = n > 0 ? Double(window.filter(\.elbow).count) / n : 0
        f.alignViolationFrac = n > 0 ? Double(window.filter(\.align).count) / n : 0
        f.armLengthPx = median(armLengths)
        return f
    }
}

// MARK: Camera compressions (fallback when there's no watch)

nonisolated struct CameraCompression {
    var t: Double
    var instRateCpm: Double?
    var amplitudePx: Double?
}

/// Zig-zag detector on wrist height: a compression bottom is a local max of image y.
nonisolated struct CameraCompressionDetector {
    private var smoothed: Double?
    private var seekingBottom = true
    private var ext: (t: Double, y: Double)?
    private var lastBottom: (t: Double, y: Double)?
    private var lastTop: (t: Double, y: Double)?
    private var intervals: [Double] = []
    private var amplitudes: [Double] = []
    private(set) var count = 0

    var rateCpm: Double? { median(intervals).map { 60 / $0 } }
    var amplitudePx: Double? { median(amplitudes) }
    var lastT: Double? { lastBottom?.t }

    mutating func push(t: Double, yPx: Double, frameH: Double) -> CameraCompression? {
        let y = smoothed.map { PoseConfig.wristEmaAlpha * yPx + (1 - PoseConfig.wristEmaAlpha) * $0 } ?? yPx
        smoothed = y
        let prom = PoseConfig.prominence * frameH
        guard let e = ext else { ext = (t, y); return nil }
        if seekingBottom {
            if y >= e.y { ext = (t, y) } else if e.y - y >= prom {
                seekingBottom = false
                ext = (t, y)
                return commitBottom(e)
            }
        } else {
            if y <= e.y { ext = (t, y) } else if y - e.y >= prom {
                lastTop = e
                seekingBottom = true
                ext = (t, y)
            }
        }
        return nil
    }

    private mutating func commitBottom(_ b: (t: Double, y: Double)) -> CameraCompression? {
        if let lb = lastBottom, b.t - lb.t < PoseConfig.minDistance { return nil }
        let interval = lastBottom.map { b.t - $0.t }
        var inst: Double?
        if let iv = interval, iv <= PoseConfig.maxInterval {
            intervals.append(iv)
            if intervals.count > PoseConfig.rateWindow { intervals.removeFirst() }
            inst = 60 / iv
        }
        var amp: Double?
        if let top = lastTop, lastBottom == nil || top.t > lastBottom!.t {
            amp = b.y - top.y
            amplitudes.append(amp!)
            if amplitudes.count > PoseConfig.depthWindow { amplitudes.removeFirst() }
        }
        lastBottom = b
        count += 1
        return CameraCompression(t: b.t, instRateCpm: inst, amplitudePx: amp)
    }
}

// MARK: Fusion

nonisolated enum RateSource: String { case watch, camera }

nonisolated struct WatchSnapshot {
    var rateCpm: Double?
    var depthCm: Double?
    var depthFused = false
    var lastCompressionAge: Double?
    var count: Int
    var heartRate: Double?
    var swapRecommended: Bool
    var fatigueScore: Double
}

nonisolated struct CameraSnapshot {
    var on: Bool
    var lastCompressionAge: Double?
    var posture: PostureFrame?
    var rateCpm: Double?
    var amplitudePx: Double?
    var count: Int
    /// Camera scale learned from the watch by DepthFusion; makes camera depth metric.
    var fusedCmPerPx: Double? = nil
}

/// Where the depth number comes from, best first.
nonisolated enum DepthSource: String, Sendable {
    case fused = "watch + camera"
    case watch
    case cameraCalibrated = "camera, calibrated"
    case cameraEstimate = "camera"
}

nonisolated struct LiveState {
    var rateCpm: Double?
    var rateSource: RateSource?
    var depthCm: Double?
    var depthEstimate = false
    var depthSource: DepthSource?
    var lastCompressionAge: Double?
    var count = 0
    var postureAvailable = false
    var elbowAngleDeg: Double?
    var elbowViolation = false
    var alignViolation = false
    var heartRate: Double?
    var swapRecommended = false
    var fatigueScore: Double?
}

nonisolated func cameraCmPerPx(_ cam: CameraSnapshot) -> Double? {
    guard let arm = cam.posture?.armLengthPx, arm > 0 else { return nil }
    return PoseConfig.armLengthCm / arm
}

nonisolated func fuse(watch: WatchSnapshot?, camera cam: CameraSnapshot) -> LiveState {
    var s = LiveState()
    let watchFresh = watch?.lastCompressionAge.map { $0 <= CoachConfig.watchFresh } ?? false
    let camFresh = cam.on && (cam.lastCompressionAge.map { $0 <= CoachConfig.stale } ?? false)
    if watchFresh, let w = watch {
        s.rateCpm = w.rateCpm; s.rateSource = .watch
        s.depthCm = w.depthCm
        if w.depthCm != nil { s.depthSource = w.depthFused ? .fused : .watch }
        s.count = w.count
    } else if camFresh {
        s.rateCpm = cam.rateCpm; s.rateSource = .camera
        s.count = cam.count
    }
    if s.depthCm == nil, camFresh, let amp = cam.amplitudePx {
        if let k = cam.fusedCmPerPx {
            // The watch dropped out, but it already taught the camera its scale.
            s.depthCm = amp * k
            s.depthSource = .cameraCalibrated
        } else if let k = cameraCmPerPx(cam) {
            s.depthCm = amp * k
            s.depthEstimate = true
            s.depthSource = .cameraEstimate
        }
    }
    s.lastCompressionAge = [watch?.lastCompressionAge, cam.on ? cam.lastCompressionAge : nil].compactMap { $0 }.min()
    if cam.on, let p = cam.posture, p.visible {
        s.postureAvailable = true
        s.elbowAngleDeg = p.elbowAngleDeg
        s.elbowViolation = p.elbowViolationFrac >= PoseConfig.postureWindowFrac
        s.alignViolation = p.alignViolationFrac >= PoseConfig.postureWindowFrac
    }
    s.heartRate = watch?.heartRate
    s.swapRecommended = watch?.swapRecommended ?? false
    s.fatigueScore = watch?.fatigueScore
    return s
}

// MARK: Coach

nonisolated enum CoachTone { case urgent, warning, swap, good }

nonisolated struct CoachRule: Sendable {
    let id: String
    let priority: Int
    let line: String
    let banner: String
    let tone: CoachTone
    let duringWarmup: Bool
    let cooldown: Double
    let active: @Sendable (LiveState, _ runningS: Double, _ allGreenS: Double) -> Bool
}

/// Depth that's trustworthy enough to coach on: measured by the watch. The phone's camera-only
/// estimate (from arm length, uncalibrated) is shown but never drives "Push harder"/"Less force".
nonisolated func coachableDepth(_ l: LiveState) -> Double? { l.depthEstimate ? nil : l.depthCm }

nonisolated func isAllGreen(_ l: LiveState) -> Bool {
    guard let age = l.lastCompressionAge, age < CoachConfig.noCompression,
          let r = l.rateCpm, r >= Targets.rateMin, r <= Targets.rateMax else { return false }
    if let d = coachableDepth(l), d < Targets.depthMin || d > Targets.depthMax { return false }
    return !l.elbowViolation && !l.alignViolation && !l.swapRecommended
}

nonisolated let coachRules: [CoachRule] = [
    CoachRule(id: "no_compressions", priority: 1, line: "Keep pushing! Don't stop.", banner: "Keep pushing", tone: .urgent,
              duringWarmup: true, cooldown: CoachConfig.ruleCooldown) { l, running, _ in
        l.lastCompressionAge.map { $0 >= CoachConfig.noCompression } ?? (running >= CoachConfig.noCompression)
    },
    CoachRule(id: "swap", priority: 2, line: "Switch rescuers now.", banner: "Switch rescuers", tone: .swap,
              duringWarmup: false, cooldown: CoachConfig.ruleCooldown) { l, _, _ in l.swapRecommended },
    CoachRule(id: "too_shallow", priority: 3, line: "Push harder.", banner: "Push harder", tone: .urgent,
              duringWarmup: false, cooldown: CoachConfig.ruleCooldown) { l, _, _ in (coachableDepth(l) ?? 99) < Targets.depthMin },
    CoachRule(id: "too_slow", priority: 4, line: "Faster.", banner: "Faster", tone: .warning,
              duringWarmup: false, cooldown: CoachConfig.ruleCooldown) { l, _, _ in (l.rateCpm ?? 999) < Targets.rateMin },
    CoachRule(id: "too_fast", priority: 5, line: "Slow down.", banner: "Slow down", tone: .warning,
              duringWarmup: false, cooldown: CoachConfig.ruleCooldown) { l, _, _ in (l.rateCpm ?? 0) > Targets.rateMax },
    CoachRule(id: "elbows_bent", priority: 6, line: "Lock your elbows.", banner: "Lock your elbows", tone: .warning,
              duringWarmup: false, cooldown: CoachConfig.ruleCooldown) { l, _, _ in l.elbowViolation },
    CoachRule(id: "not_over_hands", priority: 7, line: "Shoulders over your hands.", banner: "Shoulders over hands", tone: .warning,
              duringWarmup: false, cooldown: CoachConfig.ruleCooldown) { l, _, _ in l.alignViolation },
    CoachRule(id: "too_deep", priority: 9, line: "A little less force.", banner: "Less force", tone: .warning,
              duringWarmup: false, cooldown: CoachConfig.ruleCooldown) { l, _, _ in (coachableDepth(l) ?? 0) > CoachConfig.tooDeepCm },
    CoachRule(id: "praise", priority: 10, line: "Great compressions, keep going.", banner: "Great compressions", tone: .good,
              duringWarmup: true, cooldown: CoachConfig.praiseCooldown) { _, _, green in green >= CoachConfig.praiseAfter },
]

/// Picks the top active rule for the banner and decides whether to speak (global gap + per-rule cooldown).
nonisolated struct CoachEngine {
    private var lastSpoken = -Double.infinity
    private var ruleSpoken: [String: Double] = [:]
    private var greenSince: Double?

    mutating func reset() { self = CoachEngine() }

    mutating func evaluate(_ live: LiveState, runningS: Double, now: Double) -> (banner: CoachRule?, speak: CoachRule?) {
        greenSince = isAllGreen(live) ? (greenSince ?? now) : nil
        let green = greenSince.map { now - $0 } ?? 0
        let warmup = runningS < CoachConfig.warmup
        let active = coachRules.filter { (!warmup || $0.duringWarmup) && $0.active(live, runningS, green) }.sorted { $0.priority < $1.priority }
        var speak: CoachRule?
        if now - lastSpoken >= CoachConfig.globalGap {
            speak = active.first { now - (ruleSpoken[$0.id] ?? -.infinity) >= $0.cooldown }
            if let s = speak {
                lastSpoken = now
                ruleSpoken[s.id] = now
            }
        }
        return (active.first, speak)
    }
}

// MARK: Scoring

/// PRD §8.5; fractions 0–1, missing terms dropped and the rest reweighted. No rate data → 0.
nonisolated func computeScore(ratePct: Double?, depthPct: Double?, ccf: Double?, elbowPct: Double?, alignPct: Double?) -> Double {
    guard ratePct != nil else { return 0 }
    let terms: [(Double, Double?)] = [(30, ratePct), (30, depthPct), (20, ccf.map { min($0 / Targets.ccfTarget, 1) }), (10, elbowPct), (10, alignPct)]
    let used = terms.compactMap { w, v in v.map { (w, $0) } }
    let total = used.reduce(0) { $0 + $1.0 }
    return total > 0 ? 100 * used.reduce(0) { $0 + $1.0 * $1.1 } / total : 0
}

nonisolated func gradeLetter(_ score: Double) -> String {
    score >= 90 ? "A" : score >= 80 ? "B" : score >= 70 ? "C" : score >= 60 ? "D" : "F"
}

nonisolated struct SessionSummary {
    var score: Double
    var grade: String
    var compressions: Int
    var elapsed: Double
    var ratePct: Double?
    var depthPct: Double?
    var depthEstimated: Bool
    var ccf: Double?
    var pauses: Int
    var longestPause: Double
    var avgRate: Double?
    var avgDepth: Double?
    var elbowPct: Double?
    var alignPct: Double?
    var source: RateSource?
}

/// Session clock, pauses/CCF, per-compression grading and posture percentages.
nonisolated struct SessionTracker {
    let startedAt: Double
    private var clockStart: Double?
    private var lastCompression: Double?
    private var pauseCount = 0
    private var longestPause = 0.0
    private var handsOff = 0.0
    private var rateOk: [Bool] = [], depthOk: [Bool] = [], rates: [Double] = [], depths: [Double] = []
    private var graded = 0
    private var depthEstimated = false
    private var source: RateSource?
    private var postureTicks = 0, lockedTicks = 0, alignedTicks = 0

    init(startedAt: Double) { self.startedAt = startedAt }

    private mutating func settle(_ now: Double) {
        if clockStart == nil && now - startedAt >= CoachConfig.sessionClockGrace { clockStart = startedAt + CoachConfig.sessionClockGrace }
    }

    /// A compression from whichever source is primary right now.
    mutating func onCompression(t: Double, instRate: Double?, depth: Double?, estimated: Bool, from src: RateSource) {
        if t < startedAt { return }
        if let l = lastCompression, t - l < 0.2 { return }
        settle(t)
        if clockStart == nil { clockStart = t }
        let gap = t - (lastCompression ?? clockStart!)
        if gap > Targets.pauseThreshold {
            pauseCount += 1
            longestPause = max(longestPause, gap)
            handsOff += gap
        }
        lastCompression = max(t, lastCompression ?? t)
        graded += 1
        source = src
        if let r = instRate {
            rates.append(r)
            rateOk.append(r >= Targets.rateMin && r <= Targets.rateMax)
        }
        if let d = depth {
            depths.append(d)
            depthOk.append(d >= Targets.depthMin && d <= Targets.depthMax)
            depthEstimated = depthEstimated || estimated
        }
    }

    mutating func onPosture(_ p: PostureFrame?) {
        guard let p, p.visible else { return }
        postureTicks += 1
        if p.elbowsLocked == true { lockedTicks += 1 }
        if p.aligned == true { alignedTicks += 1 }
    }

    mutating func elapsed(_ now: Double) -> Double {
        settle(now)
        return clockStart.map { max(0, now - $0) } ?? 0
    }

    mutating func finish(_ now: Double) -> SessionSummary {
        let el = elapsed(now)
        func frac(_ xs: [Bool]) -> Double? { xs.isEmpty ? nil : Double(xs.filter { $0 }.count) / Double(xs.count) }
        let posture = postureTicks >= 10
        let ratePct = frac(rateOk), depthPct = frac(depthOk)
        let ccf = el > 0 ? max(0, (el - handsOff) / el) : nil
        let elbow = posture ? Double(lockedTicks) / Double(postureTicks) : nil
        let align = posture ? Double(alignedTicks) / Double(postureTicks) : nil
        let score = computeScore(ratePct: ratePct, depthPct: depthPct, ccf: ccf, elbowPct: elbow, alignPct: align)
        return SessionSummary(score: score, grade: gradeLetter(score), compressions: graded, elapsed: el,
                              ratePct: ratePct, depthPct: depthPct, depthEstimated: depthEstimated, ccf: ccf,
                              pauses: pauseCount, longestPause: longestPause, avgRate: median(rates), avgDepth: median(depths),
                              elbowPct: elbow, alignPct: align, source: source)
    }
}
