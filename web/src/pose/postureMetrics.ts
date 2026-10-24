// Posture metrics from pose landmarks: picks the more visible arm, then tracks elbow angle,
// shoulders-over-hands alignment, the wrist-y signal, and rolling violation fractions.
import { POSE, TARGETS } from "../config";

export interface Landmark {
  x: number;
  y: number;
  visibility?: number;
}

export interface Point {
  x: number;
  y: number;
}

export type Side = "left" | "right";

const ARM: Record<Side, { shoulder: number; elbow: number; wrist: number }> = {
  left: { shoulder: 11, elbow: 13, wrist: 15 },
  right: { shoulder: 12, elbow: 14, wrist: 16 },
};

export interface PostureFrame {
  t: number;
  side: Side;
  visible: boolean;
  shoulder: Point | null;
  elbow: Point | null;
  wrist: Point | null;
  elbowAngleDeg: number | null;
  alignAngleDeg: number | null;
  elbowsLocked: boolean | null;
  aligned: boolean | null;
  /** Fault held long enough to count (≥ violationHoldS). */
  elbowViolation: boolean;
  alignViolation: boolean;
  /** Fraction of the recent window (visible frames only) spent in violation. */
  elbowViolationFrac: number;
  alignViolationFrac: number;
  armLengthPx: number | null;
}

/** Angle at b between a and c, in degrees. */
export function angleDeg(a: Point, b: Point, c: Point): number {
  const v1x = a.x - b.x;
  const v1y = a.y - b.y;
  const v2x = c.x - b.x;
  const v2y = c.y - b.y;
  const n = Math.hypot(v1x, v1y) * Math.hypot(v2x, v2y);
  if (n === 0) return 0;
  const cos = Math.min(1, Math.max(-1, (v1x * v2x + v1y * v2y) / n));
  return (Math.acos(cos) * 180) / Math.PI;
}

/** Angle of the shoulder→wrist vector from straight down (image y grows downward). */
export function fromVerticalDeg(shoulder: Point, wrist: Point): number {
  const dx = wrist.x - shoulder.x;
  const dy = wrist.y - shoulder.y;
  return (Math.atan2(Math.abs(dx), dy) * 180) / Math.PI;
}

function armVisibility(lms: Landmark[], side: Side): number {
  const a = ARM[side];
  return Math.min(
    lms[a.shoulder]?.visibility ?? 0,
    lms[a.elbow]?.visibility ?? 0,
    lms[a.wrist]?.visibility ?? 0,
  );
}

function meanArmVisibility(lms: Landmark[], side: Side): number {
  const a = ARM[side];
  return (
    ((lms[a.shoulder]?.visibility ?? 0) + (lms[a.elbow]?.visibility ?? 0) + (lms[a.wrist]?.visibility ?? 0)) / 3
  );
}

function median(xs: number[]): number {
  const s = [...xs].sort((a, b) => a - b);
  const m = s.length >> 1;
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
}

interface WindowEntry {
  t: number;
  elbow: boolean;
  align: boolean;
}

export class PostureTracker {
  private side: Side = "left";
  private elbowEma: number | null = null;
  private bentSince: number | null = null;
  private misalignedSince: number | null = null;
  private window: WindowEntry[] = [];
  private armLengths: number[] = [];

  /** `lms` are normalized MediaPipe landmarks; w/h convert them to pixels before any geometry. */
  update(lms: Landmark[] | null, w: number, h: number, t: number): PostureFrame {
    this.window = this.window.filter((e) => t - e.t <= POSE.postureWindowS);

    if (lms && lms.length > 16) {
      const other: Side = this.side === "left" ? "right" : "left";
      if (meanArmVisibility(lms, other) > meanArmVisibility(lms, this.side) + POSE.sideSwitchMargin) {
        this.side = other;
        this.elbowEma = null;
      }
    }

    if (!lms || lms.length <= 16 || armVisibility(lms, this.side) < POSE.minVisibility) {
      this.elbowEma = null;
      this.bentSince = null;
      this.misalignedSince = null;
      return this.frame(t, false, null, null, null, null, null);
    }

    const a = ARM[this.side];
    const px = (i: number): Point => ({ x: lms[i].x * w, y: lms[i].y * h });
    const shoulder = px(a.shoulder);
    const elbow = px(a.elbow);
    const wrist = px(a.wrist);

    const rawElbow = angleDeg(shoulder, elbow, wrist);
    this.elbowEma =
      this.elbowEma === null ? rawElbow : POSE.elbowEmaAlpha * rawElbow + (1 - POSE.elbowEmaAlpha) * this.elbowEma;
    const align = fromVerticalDeg(shoulder, wrist);

    this.armLengths.push(Math.hypot(wrist.x - shoulder.x, wrist.y - shoulder.y));
    if (this.armLengths.length > POSE.armLengthSamples) this.armLengths.shift();

    return this.frame(t, true, shoulder, elbow, wrist, this.elbowEma, align);
  }

  private frame(
    t: number,
    visible: boolean,
    shoulder: Point | null,
    elbow: Point | null,
    wrist: Point | null,
    elbowAngleDeg: number | null,
    alignAngleDeg: number | null,
  ): PostureFrame {
    const elbowsLocked = elbowAngleDeg === null ? null : elbowAngleDeg >= TARGETS.elbow_locked_min_deg;
    const aligned = alignAngleDeg === null ? null : alignAngleDeg <= TARGETS.shoulder_over_hands_max_deg;

    if (elbowsLocked === false) this.bentSince ??= t;
    else this.bentSince = null;
    if (aligned === false) this.misalignedSince ??= t;
    else this.misalignedSince = null;

    const elbowViolation = this.bentSince !== null && t - this.bentSince >= POSE.violationHoldS;
    const alignViolation = this.misalignedSince !== null && t - this.misalignedSince >= POSE.violationHoldS;

    if (visible) this.window.push({ t, elbow: elbowViolation, align: alignViolation });
    const n = this.window.length;
    const frac = (k: "elbow" | "align") => (n ? this.window.filter((e) => e[k]).length / n : 0);

    return {
      t,
      side: this.side,
      visible,
      shoulder,
      elbow,
      wrist,
      elbowAngleDeg,
      alignAngleDeg,
      elbowsLocked,
      aligned,
      elbowViolation,
      alignViolation,
      elbowViolationFrac: frac("elbow"),
      alignViolationFrac: frac("align"),
      armLengthPx: this.armLengths.length ? median(this.armLengths) : null,
    };
  }
}
