// Thresholds for the on-phone coach. Mirrors shared/targets.json (AHA adult CPR targets) and the
// tunables in backend/app/config.py and web/src/config.ts, so phone and laptop behave the same.
import Foundation

nonisolated enum Targets {
    static let rateMin = 100.0
    static let rateMax = 120.0
    static let rateTarget = 110
    static let depthMin = 5.0
    static let depthMax = 6.0
    static let pauseThreshold = 2.0
    static let ccfTarget = 0.80
    static let rescuerSwap = 120.0
    static let elbowLockedMinDeg = 160.0
    static let shoulderOverHandsMaxDeg = 15.0
}

nonisolated enum DSPConfig {
    static let gravity = 9.80665
    static let imuHz = 100.0
    /// scipy.signal.butter(2, [0.5, 5], btype="band", fs=100, output="sos") — 2 biquad sections.
    static let bandpassSOS: [[Double]] = [
        [0.016581931669303045, 0.03316386333860609, 0.016581931669303045, 1.0, -1.6288507685741764, 0.6994634776474277],
        [1.0, -2.0, 1.0, 1.0, -1.9573890395427322, 0.9585316851827481],
    ]
    /// scipy.signal.sosfilt_zi for the sections above (steady state for a unit step).
    static let bandpassZi: [[Double]] = [
        [0.9227351905275812, -0.6404360892363036],
        [-0.9393171221968845, 0.9393171221968845],
    ]
    static let peakDistance = 0.3
    static let peakProminence = 3.0
    static let peakCommitAge = 0.25
    static let peakBuffer = 4.0
    static let maxInterval = 2.0
    static let rateWindow = 5
    static let depthWindow = 5
    static let cycleMin = 0.25
    static let cycleMax = 1.5
    static let clockOffsetWindow = 50
    static let clockJump = 5.0

    static let fatigueBaselineWindow = (10.0, 40.0)
    static let fatigueBaselineMinN = 10
    static let fatigueRecentN = 15
    static let fatigueDropFull = 0.25
    static let fatigueHRRiseFull = 30.0
    static let fatigueSwapDrop = 0.15
    static let fatigueSwapHold = 10.0
    static let fatigueSwapAfter = 60.0
    static let fatigueResetPause = 5.0
}

nonisolated enum CoachConfig {
    static let evalInterval = 0.25
    static let globalGap = 3.0
    static let ruleCooldown = 8.0
    static let warmup = 5.0
    static let noCompression = 2.0
    static let tooDeepCm = 6.5
    static let praiseAfter = 10.0
    static let praiseCooldown = 15.0
    static let watchFresh = 3.0
    static let stale = 3.0
    static let sessionClockGrace = 5.0
    static let countdown = 3
}

nonisolated enum PoseConfig {
    static let minConfidence: Float = 0.3
    static let sideSwitchMargin: Float = 0.1
    static let elbowEmaAlpha = 0.3
    static let violationHold = 0.5
    static let postureWindow = 2.0
    static let postureWindowFrac = 0.6
    static let armLengthCm = 55.0
    static let armLengthSamples = 90
    // Camera compression fallback (wrist height, normalized 0–1 image coordinates).
    static let wristEmaAlpha = 0.5
    static let minDistance = 0.3
    static let prominence = 0.015
    static let maxInterval = 2.0
    static let rateWindow = 5
    static let depthWindow = 5
}
