// Shared thresholds: AHA targets come from shared/targets.json so backend and frontend agree.
// Every other tunable used by pose, fusion and coach code lives here — no magic numbers inline.
import targetsJson from "../../shared/targets.json";

export interface Targets {
  rate_min_cpm: number;
  rate_max_cpm: number;
  rate_target_cpm: number;
  depth_min_cm: number;
  depth_max_cm: number;
  pause_threshold_s: number;
  max_hands_off_s: number;
  ccf_target: number;
  rescuer_swap_s: number;
  elbow_locked_min_deg: number;
  shoulder_over_hands_max_deg: number;
}

export const TARGETS: Targets = targetsJson;

export const HEALTH_POLL_MS = 2000;

export const POSE = {
  modelPath: "/models/pose_landmarker_full.task",
  wasmPath: "/wasm",
  videoWidth: 1280,
  videoHeight: 720,
  /** Shoulder, elbow and wrist must all exceed this for the arm to count as visible. */
  minVisibility: 0.6,
  /** Switch arms only when the other side is clearly more visible. */
  sideSwitchMargin: 0.1,
  elbowEmaAlpha: 0.3,
  /** A posture fault must persist this long before it counts as a violation. */
  violationHoldS: 0.5,
  /** Coach looks at the last N seconds of posture... */
  postureWindowS: 2.0,
  /** ...and fires when at least this fraction of it was a violation. */
  postureWindowFrac: 0.6,
  /** Typical adult shoulder-to-wrist length, used to guess cm/px before calibration. */
  armLengthCm: 55,
  armLengthSamples: 90,
} as const;

export const CAMERA_COMPRESSIONS = {
  wristEmaAlpha: 0.5,
  minDistanceS: 0.3,
  /** Minimum wrist travel, as a fraction of frame height, to count as a compression. */
  prominenceFrac: 0.015,
  /** Intervals longer than this are pauses, not compressions. */
  maxIntervalS: 2.0,
  rateWindow: 5,
  depthWindow: 5,
  recoilWindowS: 10,
  recoilTopPercentile: 0.05,
  recoilDeficitFrac: 0.15,
  recoilConsecutive: 3,
  traceS: 6,
} as const;

export const FUSION = {
  /** Prefer the watch if it reported a compression within this many seconds. */
  watchFreshS: 3,
  /** Hide rate/depth once the last compression is older than this. */
  staleS: 3,
} as const;

export const COACH = {
  evalIntervalMs: 250,
  globalGapS: 3,
  ruleCooldownS: 8,
  warmupS: 5,
  noCompressionS: 2,
  tooDeepCm: 6.5,
  praiseAfterS: 10,
  praiseCooldownS: 15,
  /** Let uncalibrated camera depth estimates drive "Push harder" / "A little less force". */
  useCameraDepth: true,
} as const;

export const SPEECH = {
  rate: 1.1,
  lang: "en",
} as const;

export const METRONOME = {
  lookaheadS: 0.1,
  tickMs: 25,
  accentEvery: 30,
  clickS: 0.03,
  freqHz: 1000,
  accentFreqHz: 1500,
} as const;

export const COUNTDOWN_S = 3;
export const UI_TICK_MS = 100;
