// Watch + camera depth fusion: an extended Kalman filter on the phone.
//
// The watch gives precise, high-rate acceleration in metres but drifts when integrated twice.
// The camera gives drift-free wrist height, but in pixels with an unknown scale. The filter's
// state is [p, v, s, b]: wrist height p (m, up positive) and velocity v, driven by the watch's
// acceleration; and the camera model y = b − s·p (s = pixels per metre, b = offset), which the
// camera measurements correct. The result is drift-free depth in centimetres, plus a camera that
// calibrates itself from the watch — so camera-only depth stays metric if the watch drops out.
//
// The two clocks don't line up exactly (Bluetooth latency, camera processing), and tens of
// milliseconds of skew ruin depth. So before fusing, the camera/watch offset is measured by
// cross-correlation: on a side view the camera's wrist height moves in phase with the watch's
// upward acceleration, so the lag that best aligns them is the clock offset.
//
// Pure Foundation/simd so it is unit-tested on the Mac.
import Foundation
import simd

nonisolated struct DepthFusion {
    // Noise model (tuned on synthetic data; see the fusion test).
    static let accelNoise = 0.4        // m/s², process noise on the acceleration input
    static let scaleDrift = 2.0        // px/m per √s, slow random walk on the camera scale
    static let offsetDrift = 6.0       // px per √s, body sway / framing drift
    static let cameraNoise = 6.0       // px, pose-landmark jitter (+ residual timing error)
    static let highPassTau = 2.0       // s, removes accelerometer bias with ~3° phase lag at CPR rates
    static let historyS = 4.0
    static let syncWindowS = 6.0       // seconds of signal used for each lag estimate
    static let syncEveryS = 2.0
    static let maxLagS = 0.25          // search ±250 ms
    static let minCorrelation = 0.6

    private(set) var x = SIMD4<Double>(0, 0, 0, 0)
    private(set) var P = simd_double4x4(diagonal: SIMD4(1, 1, 1, 1))
    private var t: Double?
    private var accelMean: Double?
    private var pendingCamera: [(t: Double, y: Double)] = []
    private(set) var cameraUpdates = 0
    private var history: [(t: Double, p: Double)] = []
    // Clock sync
    private var imuBuf: [(t: Double, a: Double)] = []
    private var camBuf: [(t: Double, y: Double)] = []
    private var lastSync = -Double.infinity
    private var pixelsPerMetreGuess = 0.0
    /// Camera timestamps minus this = watch-clock time of the same instant (seconds).
    private(set) var cameraLag: Double?

    var initialized: Bool { t != nil }
    /// Camera scale in pixels per centimetre.
    var pixelsPerCm: Double { x[2] / 100 }
    /// Relative uncertainty of the camera scale.
    var scaleUncertainty: Double { x[2] > 0 ? P[2][2].squareRoot() / x[2] : 1 }
    /// Trust the fused depth once the camera scale is pinned down by enough measurements.
    var converged: Bool { cameraLag != nil && cameraUpdates >= 60 && scaleUncertainty < 0.06 }

    mutating func reset() { self = DepthFusion() }

    /// First camera sample initialises the camera model; `pixelsPerMetreGuess` comes from arm length.
    private mutating func initialize(at time: Double, y: Double, pixelsPerMetreGuess: Double) {
        x = SIMD4(0, 0, pixelsPerMetreGuess, y)
        P = simd_double4x4(diagonal: SIMD4(0.05 * 0.05, 0.5 * 0.5, pow(0.4 * pixelsPerMetreGuess, 2), 30 * 30))
        t = time
    }

    /// A camera wrist height (image y in pixels, down positive). Queued until the watch timeline
    /// reaches it, because watch data arrives in 200 ms batches and later than camera frames.
    mutating func pushCamera(t ct: Double, y: Double, pixelsPerMetreGuess guess: Double) {
        if guess > 0 { pixelsPerMetreGuess = guess }
        camBuf.append((ct, y))
        camBuf.removeAll { ct - $0.t > Self.syncWindowS + 1 }
        if ct - lastSync >= Self.syncEveryS { syncClocks(now: ct) }
        guard let lag = cameraLag else { return } // don't fuse until the clocks are aligned
        let aligned = ct - lag
        if t == nil {
            guard pixelsPerMetreGuess > 0 else { return }
            initialize(at: aligned, y: y, pixelsPerMetreGuess: pixelsPerMetreGuess)
            return
        }
        pendingCamera.append((aligned, y))
        if pendingCamera.count > 120 { pendingCamera.removeFirst(pendingCamera.count - 120) }
    }

    /// Finds the lag that best aligns camera wrist height with watch acceleration.
    private mutating func syncClocks(now: Double) {
        lastSync = now
        let cams = camBuf.filter { now - $0.t <= Self.syncWindowS }
        guard cams.count >= 60, imuBuf.count >= 200 else { return }
        let ym = cams.reduce(0) { $0 + $1.y } / Double(cams.count)
        func accel(at time: Double) -> Double? {
            // Linear interpolation in the (time-ordered) IMU buffer.
            var lo = 0, hi = imuBuf.count - 1
            guard time >= imuBuf[lo].t, time <= imuBuf[hi].t else { return nil }
            while hi - lo > 1 {
                let mid = (lo + hi) / 2
                if imuBuf[mid].t <= time { lo = mid } else { hi = mid }
            }
            let a = imuBuf[lo], b = imuBuf[hi]
            let w = b.t > a.t ? (time - a.t) / (b.t - a.t) : 0
            return a.a + w * (b.a - a.a)
        }
        var best: (lag: Double, r: Double)?
        var lag = -Self.maxLagS
        while lag <= Self.maxLagS {
            var sxy = 0.0, sxx = 0.0, syy = 0.0, n = 0
            for c in cams {
                guard let a = accel(at: c.t - lag) else { continue }
                let yv = c.y - ym
                sxy += yv * a; sxx += a * a; syy += yv * yv; n += 1
            }
            if n >= 60, sxx > 0, syy > 0 {
                let r = sxy / (sxx * syy).squareRoot()
                if best == nil || r > best!.r { best = (lag, r) }
            }
            lag += 0.005
        }
        guard let b = best, b.r >= Self.minCorrelation else { return }
        cameraLag = cameraLag.map { 0.7 * $0 + 0.3 * b.lag } ?? b.lag
    }

    /// One watch sample: upward acceleration (m/s²) at phone time `at`.
    mutating func pushIMU(at time: Double, aUp: Double) {
        let previous = imuBuf.last?.t
        if let previous, time <= previous { return }
        // Remove accelerometer bias with a slow running mean (first-order high-pass). It starts at
        // zero, not the first sample: userAcceleration already excludes gravity, and seeding with a
        // mid-compression sample would inject a large phantom force for seconds.
        let alpha = min(1, (time - (previous ?? time)) / Self.highPassTau)
        let mean = (accelMean ?? 0) + alpha * (aUp - (accelMean ?? 0))
        accelMean = mean
        let a = aUp - mean
        imuBuf.append((time, a))
        if imuBuf.count > Int((Self.syncWindowS + 1) * 100) { imuBuf.removeFirst(imuBuf.count - Int((Self.syncWindowS + 1) * 100)) }
        guard let current = t, time > current else { return }

        pendingCamera.sort { $0.t < $1.t }
        while let first = pendingCamera.first, first.t <= time {
            pendingCamera.removeFirst()
            if first.t > t! {
                predict(to: first.t, accel: a)
                update(y: first.y)
            }
        }
        predict(to: time, accel: a)
        history.append((time, x[0]))
        while let h = history.first, time - h.t > Self.historyS { history.removeFirst() }
    }

    private mutating func predict(to time: Double, accel a: Double) {
        guard let current = t else { return }
        let dt = time - current
        guard dt > 0 else { return }
        x[0] += x[1] * dt + 0.5 * a * dt * dt
        x[1] += a * dt
        let F = simd_double4x4(rows: [
            SIMD4(1, dt, 0, 0),
            SIMD4(0, 1, 0, 0),
            SIMD4(0, 0, 1, 0),
            SIMD4(0, 0, 0, 1),
        ])
        let qa = Self.accelNoise * Self.accelNoise
        var Q = simd_double4x4(0)
        Q[0][0] = qa * pow(dt, 4) / 4
        Q[1][0] = qa * pow(dt, 3) / 2
        Q[0][1] = qa * pow(dt, 3) / 2
        Q[1][1] = qa * dt * dt
        Q[2][2] = Self.scaleDrift * Self.scaleDrift * dt
        Q[3][3] = Self.offsetDrift * Self.offsetDrift * dt
        P = F * P * F.transpose + Q
        t = time
    }

    private mutating func update(y: Double) {
        // y = b − s·p  →  H = [−s, 0, −p, 1]
        let predicted = x[3] - x[2] * x[0]
        let H = SIMD4<Double>(-x[2], 0, -x[0], 1)
        let PHt = P * H
        let S = simd_dot(H, PHt) + Self.cameraNoise * Self.cameraNoise
        guard S > 0 else { return }
        let K = PHt / S
        x += K * (y - predicted)
        // Joseph form, P = (I − KH) P (I − KH)ᵀ + K R Kᵀ, keeps P symmetric and positive.
        let KH = simd_double4x4(columns: (K * H[0], K * H[1], K * H[2], K * H[3]))
        let IKH = matrix_identity_double4x4 - KH
        let KRKt = simd_double4x4(columns: (K * K[0], K * K[1], K * K[2], K * K[3])) * (Self.cameraNoise * Self.cameraNoise)
        P = IKH * P * IKH.transpose + KRKt
        if x[2] < 1 { x[2] = 1 }
        cameraUpdates += 1
    }

    /// Peak-to-peak fused wrist travel (cm) over `[from, to]`, i.e. the depth of that compression.
    func depthCm(from: Double, to: Double) -> Double? {
        let span = history.filter { $0.t >= from && $0.t <= to }.map(\.p)
        guard span.count >= 5, let hi = span.max(), let lo = span.min() else { return nil }
        return (hi - lo) * 100
    }
}
