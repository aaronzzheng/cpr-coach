// Coach rule table (PRD §8.4): priority order, condition, spoken line and banner color.
import { COACH, TARGETS } from "../config";
import type { LiveState } from "../fusion/fuse";

export type BannerColor = "red" | "amber" | "purple" | "green";

export type RuleId =
  | "no_compressions"
  | "swap"
  | "too_shallow"
  | "too_slow"
  | "too_fast"
  | "elbows_bent"
  | "not_over_hands"
  | "incomplete_recoil"
  | "too_deep"
  | "praise";

export interface CoachContext {
  live: LiveState;
  /** Seconds since the session entered `running`. */
  runningS: number;
  /** Seconds everything has been in range, or 0. */
  allGreenS: number;
}

export interface Rule {
  id: RuleId;
  priority: number;
  line: string;
  banner: string;
  color: BannerColor;
  /** Allowed during the warm-up seconds at the start of a session. */
  duringWarmup: boolean;
  cooldownS: number;
  active: (c: CoachContext) => boolean;
}

const depthFor = (l: LiveState) => (l.depth.drivesCoach ? l.depth.cm : null);

export function isAllGreen(l: LiveState): boolean {
  if (l.lastCompressionAgeS === null || l.lastCompressionAgeS >= COACH.noCompressionS) return false;
  if (l.rate.cpm === null || l.rate.cpm < TARGETS.rate_min_cpm || l.rate.cpm > TARGETS.rate_max_cpm) return false;
  const d = depthFor(l);
  if (d !== null && (d < TARGETS.depth_min_cm || d > TARGETS.depth_max_cm)) return false;
  if (l.posture.elbowViolation || l.posture.alignViolation || l.posture.incompleteRecoil) return false;
  return !l.swapRecommended;
}

export const RULES: Rule[] = [
  {
    id: "no_compressions",
    priority: 1,
    line: "Keep pushing! Don't stop.",
    banner: "KEEP PUSHING",
    color: "red",
    duringWarmup: true,
    cooldownS: COACH.ruleCooldownS,
    active: (c) =>
      c.live.lastCompressionAgeS === null
        ? c.runningS >= COACH.noCompressionS
        : c.live.lastCompressionAgeS >= COACH.noCompressionS,
  },
  {
    id: "swap",
    priority: 2,
    line: "Switch rescuers now.",
    banner: "SWITCH RESCUERS",
    color: "purple",
    duringWarmup: false,
    cooldownS: COACH.ruleCooldownS,
    active: (c) => c.live.swapRecommended,
  },
  {
    id: "too_shallow",
    priority: 3,
    line: "Push harder.",
    banner: "PUSH HARDER",
    color: "red",
    duringWarmup: false,
    cooldownS: COACH.ruleCooldownS,
    active: (c) => {
      const d = depthFor(c.live);
      return d !== null && d < TARGETS.depth_min_cm;
    },
  },
  {
    id: "too_slow",
    priority: 4,
    line: "Faster.",
    banner: "FASTER",
    color: "amber",
    duringWarmup: false,
    cooldownS: COACH.ruleCooldownS,
    active: (c) => c.live.rate.cpm !== null && c.live.rate.cpm < TARGETS.rate_min_cpm,
  },
  {
    id: "too_fast",
    priority: 5,
    line: "Slow down.",
    banner: "SLOW DOWN",
    color: "amber",
    duringWarmup: false,
    cooldownS: COACH.ruleCooldownS,
    active: (c) => c.live.rate.cpm !== null && c.live.rate.cpm > TARGETS.rate_max_cpm,
  },
  {
    id: "elbows_bent",
    priority: 6,
    line: "Lock your elbows.",
    banner: "LOCK YOUR ELBOWS",
    color: "amber",
    duringWarmup: false,
    cooldownS: COACH.ruleCooldownS,
    active: (c) => c.live.posture.elbowViolation,
  },
  {
    id: "not_over_hands",
    priority: 7,
    line: "Shoulders over your hands.",
    banner: "SHOULDERS OVER HANDS",
    color: "amber",
    duringWarmup: false,
    cooldownS: COACH.ruleCooldownS,
    active: (c) => c.live.posture.alignViolation,
  },
  {
    id: "incomplete_recoil",
    priority: 8,
    line: "Let the chest come all the way up.",
    banner: "FULL RECOIL",
    color: "amber",
    duringWarmup: false,
    cooldownS: COACH.ruleCooldownS,
    active: (c) => c.live.posture.incompleteRecoil === true,
  },
  {
    id: "too_deep",
    priority: 9,
    line: "A little less force.",
    banner: "LESS FORCE",
    color: "amber",
    duringWarmup: false,
    cooldownS: COACH.ruleCooldownS,
    active: (c) => {
      const d = depthFor(c.live);
      return d !== null && d > COACH.tooDeepCm;
    },
  },
  {
    id: "praise",
    priority: 10,
    line: "Great compressions, keep going.",
    banner: "GREAT COMPRESSIONS",
    color: "green",
    duringWarmup: true,
    cooldownS: COACH.praiseCooldownS,
    active: (c) => c.allGreenS >= COACH.praiseAfterS,
  },
];
