// Skills check: a timed 2-minute test, passed when every measured skill is at 80% or better
// (rate always required). Same rule as the phone (SkillsCheck in Handoff.swift).
import type { Summary } from "../net/api";

export const SKILLS = { durationS: 120, passFraction: 0.8 } as const;

export interface Criterion {
  name: string;
  value: number | null;
}

export function criteria(s: Summary): Criterion[] {
  return [
    { name: "Rate 100–120", value: s.rate_pct },
    { name: "Depth on target", value: s.depth_estimated ? null : s.depth_pct },
    { name: "Hands on chest", value: s.ccf },
    { name: "Elbows locked", value: s.elbow_pct },
    { name: "Shoulders over hands", value: s.align_pct },
  ];
}

export const criterionPassed = (c: Criterion) => (c.value === null ? null : c.value >= SKILLS.passFraction);

export function passed(s: Summary): boolean {
  if (s.rate_pct === null || (s.elapsed_s ?? 0) < SKILLS.durationS - 5) return false;
  return criteria(s).every((c) => criterionPassed(c) !== false);
}
