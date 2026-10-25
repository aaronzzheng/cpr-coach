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

// MARK: Hand placement

/// Shoulder and hip midpoints of a body, image pixels.
nonisolated struct Torso: Sendable {
    var shoulder: CGPoint, hip: CGPoint
    /// 1 = standing/kneeling upright, 0 = lying flat.
    var uprightness: Double {
        let dx = abs(Double(hip.x - shoulder.x)), dy = abs(Double(hip.y - shoulder.y))
        return dx + dy > 0 ? dy / (dx + dy) : 0.5
    }
}

nonisolated enum HandPlacement: Equatable { case tooLow, tooHigh }

/// Where the rescuer's hands are along the patient's torso: 0 at the shoulders, 1 at the hips.
/// The target (lower half of the breastbone) sits at roughly 0.2–0.45 seen from the side.
nonisolated func torsoFraction(wrist: CGPoint, torso: Torso) -> Double? {
    let ax = Double(torso.hip.x - torso.shoulder.x), ay = Double(torso.hip.y - torso.shoulder.y)
    let len2 = ax * ax + ay * ay
    guard len2 > 1 else { return nil }
    return (Double(wrist.x - torso.shoulder.x) * ax + Double(wrist.y - torso.shoulder.y) * ay) / len2
}

/// Flags hands too far toward the belly or the neck, once it has lasted a couple of seconds.
nonisolated struct HandPlacementTracker {
    static let range = 0.12...0.55
    static let holdS = 2.0
    private var since: (issue: HandPlacement, t: Double)?
    private(set) var issue: HandPlacement?

    mutating func reset() { self = HandPlacementTracker() }

    mutating func update(t: Double, wrist: CGPoint?, torso: Torso?) {
        guard let wrist, let torso, let f = torsoFraction(wrist: wrist, torso: torso), (-0.3...1.3).contains(f) else {
            since = nil; issue = nil; return  // no patient in view: say nothing
        }
        let now: HandPlacement? = f > Self.range.upperBound ? .tooLow : f < Self.range.lowerBound ? .tooHigh : nil
        guard let now else { since = nil; issue = nil; return }
        if since?.issue != now { since = (now, t) }
        issue = t - since!.t >= Self.holdS ? now : nil
    }
}

// MARK: Camera compressions (fallback when there's no watch)

nonisolated struct CameraCompression {
    var t: Double
    var instRateCpm: Double?
    var amplitudePx: Double?
    /// Wrist height (image y, px) at the top of the stroke before this compression.
    var topY: Double? = nil
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
        var topY: Double?
        if let top = lastTop, lastBottom == nil || top.t > lastBottom!.t {
            amp = b.y - top.y
            topY = top.y
            amplitudes.append(amp!)
            if amplitudes.count > PoseConfig.depthWindow { amplitudes.removeFirst() }
        }
        lastBottom = b
        count += 1
        return CameraCompression(t: b.t, instRateCpm: inst, amplitudePx: amp, topY: topY)
    }
}

// MARK: Fatigue forecast

/// Predicts when the rescuer's depth will fall below the target, from the trend of recent
/// per-compression depths, so the coach can call a swap before quality drops rather than after.
/// A least-squares line over the last ~45 s; it only warns when the downward slope is
/// statistically clear (noise in single compressions is about ±0.5 cm).
nonisolated struct SwapForecaster {
    private var pts: [(t: Double, d: Double)] = []
    private var since: Double?

    mutating func reset() { self = SwapForecaster() }

    /// The forecast, once it has held for a few seconds (one noisy stretch shouldn't call a swap).
    mutating func update(now: Double, limit: Double) -> Double? {
        guard let s = secondsToShallow(now: now, limit: limit) else { since = nil; return nil }
        since = since ?? now
        return now - since! >= ForecastConfig.holdS ? s : nil
    }

    mutating func push(t: Double, depth: Double) {
        pts.append((t, depth))
        pts.removeAll { t - $0.t > ForecastConfig.windowS }
    }

    /// Seconds until the trend crosses `limit`, if it is falling and will within the horizon.
    func secondsToShallow(now: Double, limit: Double) -> Double? {
        guard pts.count >= ForecastConfig.minPoints, let first = pts.first, let last = pts.last,
              last.t - first.t >= ForecastConfig.minSpanS else { return nil }
        let n = Double(pts.count)
        let mt = pts.reduce(0) { $0 + $1.t } / n
        let md = pts.reduce(0) { $0 + $1.d } / n
        var stt = 0.0, std = 0.0
        for p in pts { stt += (p.t - mt) * (p.t - mt); std += (p.t - mt) * (p.d - md) }
        guard stt > 0 else { return nil }
        let slope = std / stt
        let intercept = md - slope * mt
        var sse = 0.0
        for p in pts { let r = p.d - (intercept + slope * p.t); sse += r * r }
        let se = (sse / max(1, n - 2) / stt).squareRoot()
        guard slope < 0, slope < -ForecastConfig.significance * se else { return nil }
        let dNow = intercept + slope * now
        guard dNow >= limit else { return nil } // already shallow: the depth rule handles it
        let s = (limit - dNow) / slope
        return s <= ForecastConfig.horizonS ? s : nil
    }
}

// MARK: Recoil

/// Incomplete chest recoil (leaning): the hands stop short of the chest's resting height between
/// compressions. The patient and the phone don't move, so the highest wrist positions over the
/// last stretch of compressions mark the chest at rest; a stroke whose top is clearly below that
/// is leaning. The camera's learned scale (DepthFusion) turns the pixel gap into centimetres.
nonisolated struct RecoilTracker {
    private var tops: [(t: Double, y: Double)] = []
    private(set) var recent: [Bool] = [] // true = full recoil
    private(set) var full = 0, total = 0
    private(set) var lastShortfallCm: Double?

    mutating func reset() { self = RecoilTracker() }

    /// A compression's preceding top (image y, down positive). Returns how far short it stopped (cm).
    @discardableResult
    mutating func push(t: Double, topY: Double, cmPerPx: Double) -> Double? {
        tops.append((t, topY))
        tops.removeAll { t - $0.t > RecoilConfig.referenceWindowS }
        guard tops.count >= RecoilConfig.minTops else { return nil }
        // Chest at rest = a high percentile of the stroke tops (smallest y), robust to one-off spikes.
        let ys = tops.map(\.y).sorted()
        let rest = ys[Int(Double(ys.count - 1) * RecoilConfig.restPercentile)]
        let shortfall = max(0, (topY - rest) * cmPerPx)
        lastShortfallCm = shortfall
        let ok = shortfall < RecoilConfig.maxShortfallCm
        recent.append(ok)
        if recent.count > RecoilConfig.window { recent.removeFirst() }
        total += 1
        if ok { full += 1 }
        return shortfall
    }

    /// Leaning on most of the recent compressions.
    var incomplete: Bool {
        recent.count >= RecoilConfig.window && recent.filter { !$0 }.count * 2 >= recent.count
    }

    var fullPct: Double? { total >= RecoilConfig.window ? Double(full) / Double(total) : nil }
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
    var recoilIncomplete = false
    /// Forecast seconds until depth drops below target (fatigue), when it's coming soon.
    var swapInS: Double?
    /// Waiting for two rescue breaths (30:2 mode).
    var breathPause = false
    /// Hands off the center of the chest (only when the patient is in view).
    var handPlacement: HandPlacement?
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
    if let d = coachableDepth(l), d < Targets.depthOkMin || d > Targets.depthOkMax { return false }
    return !l.elbowViolation && !l.alignViolation && !l.swapRecommended && !l.recoilIncomplete && l.handPlacement == nil
}

nonisolated let coachRules: [CoachRule] = [
    CoachRule(id: "no_compressions", priority: 1, line: "Keep pushing! Don't stop.", banner: "Keep pushing", tone: .urgent,
              duringWarmup: true, cooldown: CoachConfig.ruleCooldown) { l, running, _ in
        !l.breathPause && (l.lastCompressionAge.map { $0 >= CoachConfig.noCompression } ?? (running >= CoachConfig.noCompression))
    },
    CoachRule(id: "swap", priority: 2, line: "Switch rescuers now.", banner: "Switch rescuers", tone: .swap,
              duringWarmup: false, cooldown: CoachConfig.ruleCooldown) { l, _, _ in l.swapRecommended },
    CoachRule(id: "breaths", priority: 0, line: "Give 2 breaths.", banner: "Give 2 breaths", tone: .swap,
              duringWarmup: true, cooldown: 60) { l, _, _ in l.breathPause },
    CoachRule(id: "swap_soon", priority: 3, line: "You're tiring. Get ready to switch rescuers.", banner: "Switch soon", tone: .swap,
              duringWarmup: false, cooldown: 25) { l, _, _ in !l.swapRecommended && l.swapInS != nil },
    CoachRule(id: "too_shallow", priority: 3, line: "Push harder.", banner: "Push harder", tone: .urgent,
              duringWarmup: false, cooldown: CoachConfig.ruleCooldown) { l, _, _ in (coachableDepth(l) ?? 99) < Targets.depthOkMin },
    CoachRule(id: "too_slow", priority: 4, line: "Faster.", banner: "Faster", tone: .warning,
              duringWarmup: false, cooldown: CoachConfig.ruleCooldown) { l, _, _ in (l.rateCpm ?? 999) < Targets.rateMin },
    CoachRule(id: "too_fast", priority: 5, line: "Slow down.", banner: "Slow down", tone: .warning,
              duringWarmup: false, cooldown: CoachConfig.ruleCooldown) { l, _, _ in (l.rateCpm ?? 0) > Targets.rateMax },
    CoachRule(id: "hands_low", priority: 5, line: "Move your hands toward their head, to the center of the chest.", banner: "Hands higher on chest",
              tone: .warning, duringWarmup: false, cooldown: CoachConfig.ruleCooldown) { l, _, _ in l.handPlacement == .tooLow },
    CoachRule(id: "hands_high", priority: 5, line: "Move your hands down to the lower half of the breastbone.", banner: "Hands lower on chest",
              tone: .warning, duringWarmup: false, cooldown: CoachConfig.ruleCooldown) { l, _, _ in l.handPlacement == .tooHigh },
    CoachRule(id: "recoil", priority: 6, line: "Let the chest come all the way up.", banner: "Let the chest rise", tone: .warning,
              duringWarmup: false, cooldown: CoachConfig.ruleCooldown) { l, _, _ in l.recoilIncomplete },
    CoachRule(id: "elbows_bent", priority: 7, line: "Lock your elbows.", banner: "Lock your elbows", tone: .warning,
              duringWarmup: false, cooldown: CoachConfig.ruleCooldown) { l, _, _ in l.elbowViolation },
    CoachRule(id: "not_over_hands", priority: 8, line: "Shoulders over your hands.", banner: "Shoulders over hands", tone: .warning,
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

    /// A line the model spoke itself (e.g. the breaths prompt), so the engine doesn't repeat it.
    mutating func markSpoken(_ id: String, now: Double) {
        lastSpoken = now
        ruleSpoken[id] = now
    }

    mutating func evaluate(_ live: LiveState, runningS: Double, now: Double) -> (banner: CoachRule?, speak: CoachRule?) {
        greenSince = isAllGreen(live) ? (greenSince ?? now) : nil
        let green = greenSince.map { now - $0 } ?? 0
        let warmup = runningS < CoachConfig.warmup
        // During rescue breaths only the breaths prompt applies.
        let active = coachRules.filter {
            (!warmup || $0.duringWarmup) && (!live.breathPause || $0.id == "breaths") && $0.active(live, runningS, green)
        }.sorted { $0.priority < $1.priority }
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
nonisolated func computeScore(ratePct: Double?, depthPct: Double?, ccf: Double?, elbowPct: Double?, alignPct: Double?, recoilPct: Double? = nil) -> Double {
    guard ratePct != nil else { return 0 }
    let terms: [(Double, Double?)] = [(30, ratePct), (30, depthPct), (20, ccf.map { min($0 / Targets.ccfTarget, 1) }), (10, elbowPct), (10, alignPct), (10, recoilPct)]
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
    var recoilPct: Double? = nil
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
    private var breathPauses = 0
    private var depthEstimated = false
    private var source: RateSource?
    private var postureTicks = 0, lockedTicks = 0, alignedTicks = 0

    init(startedAt: Double) { self.startedAt = startedAt }

    private mutating func settle(_ now: Double) {
        if clockStart == nil && now - startedAt >= CoachConfig.sessionClockGrace { clockStart = startedAt + CoachConfig.sessionClockGrace }
    }

    /// A compression from whichever source is primary right now.
    /// Set when rescue breaths start: the gap before the next compression is a planned pause.
    var plannedPause = false

    mutating func onCompression(t: Double, instRate: Double?, depth: Double?, estimated: Bool, from src: RateSource) {
        if t < startedAt { return }
        if let l = lastCompression, t - l < 0.2 { return }
        settle(t)
        if clockStart == nil { clockStart = t }
        let gap = t - (lastCompression ?? clockStart!)
        if plannedPause {
            plannedPause = false
            if gap > Targets.pauseThreshold { breathPauses += 1 }
        } else if gap > Targets.pauseThreshold {
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
            depthOk.append(d >= Targets.depthOkMin && d <= Targets.depthOkMax)
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

    var recoilPct: Double?

    mutating func finish(_ now: Double) -> SessionSummary {
        let el = elapsed(now)
        func frac(_ xs: [Bool]) -> Double? { xs.isEmpty ? nil : Double(xs.filter { $0 }.count) / Double(xs.count) }
        let posture = postureTicks >= 10
        let ratePct = frac(rateOk), depthPct = frac(depthOk)
        let ccf = el > 0 ? max(0, (el - handsOff) / el) : nil
        let elbow = posture ? Double(lockedTicks) / Double(postureTicks) : nil
        let align = posture ? Double(alignedTicks) / Double(postureTicks) : nil
        let score = computeScore(ratePct: ratePct, depthPct: depthPct, ccf: ccf, elbowPct: elbow, alignPct: align, recoilPct: recoilPct)
        return SessionSummary(score: score, grade: gradeLetter(score), compressions: graded, elapsed: el,
                              ratePct: ratePct, depthPct: depthPct, depthEstimated: depthEstimated, ccf: ccf,
                              pauses: pauseCount, longestPause: longestPause, avgRate: median(rates), avgDepth: median(depths),
                              elbowPct: elbow, alignPct: align, source: source, recoilPct: recoilPct)
    }
}
