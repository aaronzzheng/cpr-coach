// On-phone watch signal processing — a Swift port of backend/app (ingest, dsp/*, pipeline).
// CPR1 packets → gravity projection → band-pass → online peaks → per-cycle depth → fatigue.
// Pure Foundation so it can be unit-tested on the Mac against the Python implementation.
import Foundation

// MARK: Packets

nonisolated struct IMUBatch {
    var seq: UInt32
    var ts: [Double]
    var ua: [SIMD3<Double>]
    var g: [SIMD3<Double>]
}

nonisolated enum CPRPacket {
    static let magic: UInt32 = 0x4350_5231

    /// Decodes a CPR1 packet (12-byte header + 44-byte rows, little-endian). Nil if malformed.
    static func decode(_ data: Data) -> IMUBatch? {
        guard data.count >= 12 else { return nil }
        return data.withUnsafeBytes { raw -> IMUBatch? in
            func u32(_ o: Int) -> UInt32 { UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: o, as: UInt32.self)) }
            func u16(_ o: Int) -> UInt16 { UInt16(littleEndian: raw.loadUnaligned(fromByteOffset: o, as: UInt16.self)) }
            func f32(_ o: Int) -> Double { Double(Float32(bitPattern: u32(o))) }
            guard u32(0) == magic else { return nil }
            let count = Int(u16(8))
            guard raw.count == 12 + count * 44 else { return nil }
            var b = IMUBatch(seq: u32(4), ts: [], ua: [], g: [])
            b.ts.reserveCapacity(count)
            for i in 0..<count {
                let o = 12 + i * 44
                b.ts.append(Double(bitPattern: UInt64(littleEndian: raw.loadUnaligned(fromByteOffset: o, as: UInt64.self))))
                b.ua.append(SIMD3(f32(o + 8), f32(o + 12), f32(o + 16)))
                b.g.append(SIMD3(f32(o + 20), f32(o + 24), f32(o + 28)))
            }
            return b
        }
    }
}

/// Counts missing batches; `check` returns true when a packet follows a gap.
nonisolated struct SeqTracker {
    private(set) var last: UInt32?
    private(set) var gaps = 0

    mutating func reset() { last = nil }

    mutating func check(_ seq: UInt32) -> Bool {
        guard let last else {
            self.last = seq
            return false
        }
        let missing = seq &- last &- 1
        let restarted = missing > 0x7FFF_FFFF
        if missing != 0 && !restarted { gaps += Int(missing) }
        self.last = seq
        return missing != 0
    }
}

// MARK: Vertical projection and filtering

/// userAcceleration projected onto gravity → upward acceleration in m/s² (orientation-independent).
nonisolated func verticalAccel(ua: SIMD3<Double>, g: SIMD3<Double>) -> Double {
    let n = (g * g).sum().squareRoot()
    guard n > 0 else { return 0 }
    return -((ua * (g / n)).sum()) * DSPConfig.gravity
}

/// Streaming biquad cascade (transposed direct form II, same as scipy.signal.sosfilt).
nonisolated struct StreamingBandpass {
    private let sos = DSPConfig.bandpassSOS
    private var zi: [[Double]]?

    mutating func reset() { zi = nil }

    mutating func process(_ x: Double) -> Double {
        if zi == nil { zi = DSPConfig.bandpassZi.map { $0.map { $0 * x } } }
        var y = x
        for s in 0..<sos.count {
            let c = sos[s]
            let input = y
            y = c[0] * input + zi![s][0]
            zi![s][0] = c[1] * input - c[4] * y + zi![s][1]
            zi![s][1] = c[2] * input - c[5] * y
        }
        return y
    }
}

// MARK: Peaks (scipy.signal.find_peaks with distance + prominence)

nonisolated func findPeaks(_ x: [Double], distance: Int, prominence: Double) -> [Int] {
    let n = x.count
    guard n >= 3 else { return [] }
    // Local maxima, with flat tops reduced to their middle sample like scipy.
    var peaks: [Int] = []
    var i = 1
    while i < n - 1 {
        if x[i - 1] < x[i] {
            var ahead = i + 1
            while ahead < n - 1 && x[ahead] == x[i] { ahead += 1 }
            if x[ahead] < x[i] {
                peaks.append((i + ahead - 1) / 2)
                i = ahead
                continue
            }
        }
        i += 1
    }
    // Distance: keep higher peaks first, drop neighbours closer than `distance`.
    if distance > 1 && peaks.count > 1 {
        var keep = [Bool](repeating: true, count: peaks.count)
        for p in peaks.indices.sorted(by: { x[peaks[$0]] > x[peaks[$1]] }) where keep[p] {
            var j = p - 1
            while j >= 0 && peaks[p] - peaks[j] < distance { keep[j] = false; j -= 1 }
            j = p + 1
            while j < peaks.count && peaks[j] - peaks[p] < distance { keep[j] = false; j += 1 }
        }
        peaks = peaks.indices.filter { keep[$0] }.map { peaks[$0] }
    }
    // Prominence: height above the higher of the two lowest points before a taller peak.
    return peaks.filter { p in
        var leftMin = x[p], j = p
        while j > 0 && x[j - 1] <= x[p] { j -= 1; leftMin = min(leftMin, x[j]) }
        var rightMin = x[p], k = p
        while k < n - 1 && x[k + 1] <= x[p] { k += 1; rightMin = min(rightMin, x[k]) }
        return x[p] - max(leftMin, rightMin) >= prominence
    }
}

// MARK: Depth

/// Per-cycle depth (cm): double integration of raw a_up between two tops with linear detrending.
nonisolated func cycleDepthCm(t: [Double], aUp: [Double], scale: Double = 1) -> Double? {
    guard t.count >= 3 else { return nil }
    let dur = t.last! - t.first!
    guard dur >= DSPConfig.cycleMin && dur <= DSPConfig.cycleMax else { return nil }
    let mean = aUp.reduce(0, +) / Double(aUp.count)
    func cumtrapz(_ y: [Double]) -> [Double] {
        var out = [0.0]
        for i in 1..<y.count { out.append(out[i - 1] + (y[i] + y[i - 1]) / 2 * (t[i] - t[i - 1])) }
        return out
    }
    func detrend(_ y: [Double]) -> [Double] {
        let span = t.last! - t.first!
        return y.indices.map { y[$0] - (y[0] + (y.last! - y[0]) * (t[$0] - t[0]) / span) }
    }
    let v = detrend(cumtrapz(aUp.map { $0 - mean }))
    let x = detrend(cumtrapz(v))
    return (x.max()! - x.min()!) * 100 * scale
}

// MARK: Compressions

nonisolated struct WatchCompression {
    var t: Double
    var intervalS: Double?
    var instRateCpm: Double?
    var depthCm: Double?
}

nonisolated func median(_ xs: [Double]) -> Double? {
    guard !xs.isEmpty else { return nil }
    let s = xs.sorted()
    let m = s.count / 2
    return s.count % 2 == 1 ? s[m] : (s[m - 1] + s[m]) / 2
}

/// Online bottoms (max a_up) and tops (min a_up) on the band-passed signal; depth filled in
/// when the cycle top→bottom→top completes. Mirrors backend/app/dsp/compressions.py.
nonisolated struct CompressionDetector {
    var depthScale: Double
    private let fs = DSPConfig.imuHz
    private var t: [Double] = []
    private var raw: [Double] = []
    private var filt: [Double] = []
    private var discontinuities: [Double] = []
    private(set) var lastBottom: Double?
    private var lastTop: Double?
    private var prevTop: Double?
    private var pending: WatchCompression?
    private var intervals: [Double] = []
    private(set) var count = 0

    init(depthScale: Double = 1) { self.depthScale = depthScale }

    var rateCpm: Double? { median(intervals).map { 60 / $0 } }

    mutating func markDiscontinuity(_ at: Double) { discontinuities.append(at) }

    mutating func push(t ts: [Double], raw r: [Double], filt f: [Double]) -> (bottoms: [WatchCompression], done: [WatchCompression]) {
        t += ts; raw += r; filt += f
        let maxN = Int(DSPConfig.peakBuffer * fs)
        if t.count > maxN {
            let drop = t.count - maxN
            t.removeFirst(drop); raw.removeFirst(drop); filt.removeFirst(drop)
        }
        if let first = t.first { discontinuities.removeAll { $0 < first } }
        var bottoms: [WatchCompression] = []
        var done: [WatchCompression] = []
        guard t.count >= 3, let now = t.last else { return (bottoms, done) }

        let dist = max(1, Int(DSPConfig.peakDistance * fs))
        var events: [(Double, Bool)] = [] // (time, isBottom)
        for isBottom in [true, false] {
            let sig = isBottom ? filt : filt.map { -$0 }
            var last = isBottom ? lastBottom : lastTop
            for i in findPeaks(sig, distance: dist, prominence: DSPConfig.peakProminence) {
                let pt = t[i]
                if now - pt < DSPConfig.peakCommitAge { continue }
                if let l = last, pt <= l + DSPConfig.peakDistance { continue }
                events.append((pt, isBottom))
                last = pt
            }
        }
        for (pt, isBottom) in events.sorted(by: { $0.0 < $1.0 }) {
            if isBottom {
                let c = commitBottom(pt)
                if let p = pending { done.append(p) }
                pending = c
                bottoms.append(c)
            } else {
                commitTop(pt)
                if let p = pending, p.t < pt {
                    done.append(p)
                    pending = nil
                }
            }
        }
        if let p = pending, now - p.t > 1.5 {
            done.append(p)
            pending = nil
        }
        return (bottoms, done)
    }

    private mutating func commitBottom(_ pt: Double) -> WatchCompression {
        let interval = lastBottom.map { pt - $0 }
        var inst: Double?
        if let iv = interval, iv <= DSPConfig.maxInterval {
            intervals.append(iv)
            if intervals.count > DSPConfig.rateWindow { intervals.removeFirst() }
            inst = 60 / iv
        }
        lastBottom = pt
        count += 1
        return WatchCompression(t: pt, intervalS: interval, instRateCpm: inst)
    }

    private mutating func commitTop(_ pt: Double) {
        prevTop = lastTop
        lastTop = pt
        guard var c = pending, let t0 = prevTop, t0 < c.t, c.t < pt else { return }
        if discontinuities.contains(where: { $0 >= t0 && $0 <= pt }) { return }
        let idx = t.indices.filter { t[$0] >= t0 && t[$0] <= pt }
        c.depthCm = cycleDepthCm(t: idx.map { t[$0] }, aUp: idx.map { raw[$0] }, scale: depthScale)
        pending = c
    }
}

// MARK: Fatigue

nonisolated struct FatigueState {
    var score = 0.0
    var baselineDepth: Double?
    var recentDepth: Double?
    var depthDrop = 0.0
    var swapRecommended = false
    var cycleElapsed = 0.0
}

nonisolated struct FatigueModel {
    private var cycleStart: Double?
    private var hrAtStart: Double?
    private var baseline: [Double] = []
    private var recent: [Double] = []
    private var dropSince: Double?
    private(set) var state = FatigueState()

    mutating func resetCycle(at t: Double?, hr: Double?) {
        self = FatigueModel()
        cycleStart = t
        hrAtStart = hr
    }

    mutating func add(t: Double, depth: Double?) {
        if cycleStart == nil { cycleStart = t }
        guard let depth, let start = cycleStart else { return }
        let (lo, hi) = DSPConfig.fatigueBaselineWindow
        if t - start >= lo && t - start <= hi { baseline.append(depth) }
        recent.append(depth)
        if recent.count > DSPConfig.fatigueRecentN { recent.removeFirst() }
    }

    @discardableResult
    mutating func update(now: Double, hr: Double?) -> FatigueState {
        guard let start = cycleStart else {
            state = FatigueState()
            return state
        }
        if hrAtStart == nil, let hr { hrAtStart = hr }
        let elapsed = now - start
        var s = FatigueState(cycleElapsed: elapsed)
        if baseline.count >= DSPConfig.fatigueBaselineMinN { s.baselineDepth = median(baseline) }
        s.recentDepth = median(recent)
        if let b = s.baselineDepth, let r = s.recentDepth, b > 0, elapsed > DSPConfig.fatigueBaselineWindow.1 {
            s.depthDrop = 1 - r / b
        }
        let hrRise = (hr != nil && hrAtStart != nil) ? hr! - hrAtStart! : 0
        func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
        s.score = clamp(0.7 * clamp(s.depthDrop / DSPConfig.fatigueDropFull) + 0.3 * clamp(hrRise / DSPConfig.fatigueHRRiseFull))
        if elapsed >= DSPConfig.fatigueSwapAfter && s.depthDrop >= DSPConfig.fatigueSwapDrop {
            dropSince = dropSince ?? now
        } else {
            dropSince = nil
        }
        let sustained = dropSince.map { now - $0 >= DSPConfig.fatigueSwapHold } ?? false
        s.swapRecommended = elapsed >= Targets.rescuerSwap || sustained
        state = s
        return s
    }
}

// MARK: Pipeline

/// Per-packet watch pipeline. DSP runs on the watch clock; outputs are mapped to `recvTime`'s
/// clock (the phone's monotonic uptime) through a rolling-minimum offset.
nonisolated struct WatchPipeline {
    var depthScale: Double { didSet { detector.depthScale = depthScale } }
    private(set) var seq = SeqTracker()
    private var filter = StreamingBandpass()
    private(set) var detector: CompressionDetector
    private(set) var fatigue = FatigueModel()
    private var offsets: [Double] = []
    private(set) var lastTs: Double?
    private var depths: [Double] = []
    var heartRate: Double?

    init(depthScale: Double = 1) {
        self.depthScale = depthScale
        detector = CompressionDetector(depthScale: depthScale)
    }

    mutating func resetDSP() {
        filter.reset()
        detector = CompressionDetector(depthScale: depthScale)
        fatigue = FatigueModel()
        offsets.removeAll()
        lastTs = nil
        depths.removeAll()
    }

    var offset: Double { offsets.min() ?? 0 }
    func toLocal(_ watchT: Double) -> Double { watchT + offset }
    var rateCpm: Double? { detector.rateCpm }
    var depthMedian: Double? { median(depths) }
    var count: Int { detector.count }
    var lastCompressionLocal: Double? { detector.lastBottom.map(toLocal) }

    mutating func swap() { fatigue.resetCycle(at: nil, hr: heartRate) }

    mutating func process(_ b: IMUBatch, recvTime: Double) -> (bottoms: [WatchCompression], done: [WatchCompression]) {
        guard let first = b.ts.first, let last = b.ts.last else { return ([], []) }
        if let lt = lastTs, first < lt - 1 {
            resetDSP()
            seq.reset()
        } else if let lt = lastTs, first - lt > DSPConfig.clockJump {
            offsets.removeAll()
            filter.reset()
            detector.markDiscontinuity(first)
        }
        if seq.check(b.seq) {
            filter.reset()
            detector.markDiscontinuity(first)
        }
        offsets.append(recvTime - last)
        if offsets.count > DSPConfig.clockOffsetWindow { offsets.removeFirst() }
        lastTs = last

        let aUp = b.ua.indices.map { verticalAccel(ua: b.ua[$0], g: b.g[$0]) }
        let filtered = aUp.map { filter.process($0) }
        let prevBottom = detector.lastBottom
        var (bottoms, done) = detector.push(t: b.ts, raw: aUp, filt: filtered)

        var pb = prevBottom
        for c in bottoms {
            if let p = pb, c.t - p > DSPConfig.fatigueResetPause { fatigue.resetCycle(at: c.t, hr: heartRate) }
            pb = c.t
        }
        for c in done {
            fatigue.add(t: c.t, depth: c.depthCm)
            if let d = c.depthCm {
                depths.append(d)
                if depths.count > DSPConfig.depthWindow { depths.removeFirst() }
            }
        }
        fatigue.update(now: last, hr: heartRate)
        let off = offset
        bottoms = bottoms.map { var c = $0; c.t += off; return c }
        done = done.map { var c = $0; c.t += off; return c }
        return (bottoms, done)
    }
}
