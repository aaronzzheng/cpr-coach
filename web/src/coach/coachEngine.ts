// Coach engine: every tick, picks the highest-priority active rule for the banner, and decides
// whether to speak it given the global gap and per-rule cooldowns.
import { COACH } from "../config";
import type { LiveState } from "../fusion/fuse";
import { isAllGreen, RULES, type Rule, type RuleId } from "./rules";

export interface CoachDecision {
  /** Top active issue; shown even while the voice is in cooldown. */
  banner: Rule | null;
  /** Rule to say right now, if any. */
  speak: Rule | null;
}

export class CoachEngine {
  private lastSpokenAt = -Infinity;
  private ruleSpokenAt = new Map<RuleId, number>();
  private greenSince: number | null = null;

  constructor(private readonly rules: Rule[] = RULES) {}

  reset(): void {
    this.lastSpokenAt = -Infinity;
    this.ruleSpokenAt.clear();
    this.greenSince = null;
  }

  /** `now` in seconds on any monotonic clock; `runningS` is time since the session started. */
  evaluate(live: LiveState, runningS: number, now: number): CoachDecision {
    if (isAllGreen(live)) this.greenSince ??= now;
    else this.greenSince = null;

    const ctx = { live, runningS, allGreenS: this.greenSince === null ? 0 : now - this.greenSince };
    const warmup = runningS < COACH.warmupS;
    const active = this.rules
      .filter((r) => (!warmup || r.duringWarmup) && r.active(ctx))
      .sort((a, b) => a.priority - b.priority);

    const banner = active[0] ?? null;
    let speak: Rule | null = null;
    if (now - this.lastSpokenAt >= COACH.globalGapS) {
      speak = active.find((r) => now - (this.ruleSpokenAt.get(r.id) ?? -Infinity) >= r.cooldownS) ?? null;
      if (speak) {
        this.lastSpokenAt = now;
        this.ruleSpokenAt.set(speak.id, now);
      }
    }
    return { banner, speak };
  }
}
