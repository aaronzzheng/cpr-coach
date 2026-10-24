import { describe, expect, it } from "vitest";
import { CoachEngine } from "../coach/coachEngine";
import type { LiveState } from "../fusion/fuse";

function live(over: Partial<{ cpm: number | null; depth: number | null; age: number | null; elbow: boolean }> = {}): LiveState {
  const o = { cpm: 110, depth: 5.5, age: 0.2, elbow: false, ...over };
  return {
    rate: { cpm: o.cpm, source: "camera" },
    depth: { cm: o.depth, estimate: true, source: "camera", drivesCoach: true },
    lastCompressionAgeS: o.age,
    compressionCount: 10,
    posture: {
      available: true,
      elbowAngleDeg: 170,
      alignAngleDeg: 5,
      elbowViolation: o.elbow,
      alignViolation: false,
      incompleteRecoil: false,
    },
    hrBpm: null,
    swapRecommended: false,
    fatigueScore: null,
  };
}

describe("CoachEngine", () => {
  it("stays quiet about form during warm-up but still says keep pushing", () => {
    const e = new CoachEngine();
    expect(e.evaluate(live({ cpm: 80 }), 1, 1).banner).toBeNull();
    expect(e.evaluate(live({ age: null }), 3, 3).speak?.id).toBe("no_compressions");
  });

  it("picks the highest priority rule", () => {
    const e = new CoachEngine();
    const d = e.evaluate(live({ cpm: 80, depth: 4, elbow: true }), 10, 10);
    expect(d.speak?.id).toBe("too_shallow");
    expect(d.banner?.id).toBe("too_shallow");
  });

  it("respects the global gap and per-rule cooldown", () => {
    const e = new CoachEngine();
    expect(e.evaluate(live({ depth: 4 }), 10, 10).speak?.id).toBe("too_shallow");
    // Within the 3 s global gap: banner yes, voice no.
    const quiet = e.evaluate(live({ depth: 4 }), 11, 11);
    expect(quiet.banner?.id).toBe("too_shallow");
    expect(quiet.speak).toBeNull();
    // After the gap, too_shallow is still cooling down, so the next issue speaks.
    expect(e.evaluate(live({ depth: 4, cpm: 130 }), 13.1, 13.1).speak?.id).toBe("too_fast");
    // After 8 s, too_shallow can repeat.
    expect(e.evaluate(live({ depth: 4 }), 18.1, 18.1).speak?.id).toBe("too_shallow");
  });

  it("praises after 10 s all green, at most every 15 s", () => {
    const e = new CoachEngine();
    const spoken: string[] = [];
    for (let t = 6; t <= 40; t += 0.25) {
      const s = e.evaluate(live(), t, t).speak;
      if (s) spoken.push(`${s.id}@${t}`);
    }
    expect(spoken).toEqual(["praise@16", "praise@31"]);
  });
});
