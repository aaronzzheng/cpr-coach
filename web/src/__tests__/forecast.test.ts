import { describe, expect, it } from "vitest";
import { SwapForecaster } from "../fusion/forecast";

// Deterministic pseudo-noise (±0.45 cm), so the test doesn't flake.
function noise(i: number): number {
  const x = Math.sin(i * 12.9898) * 43758.5453;
  return (x - Math.floor(x) - 0.5) * 0.9;
}

describe("SwapForecaster", () => {
  it("never warns for a steady rescuer", () => {
    const f = new SwapForecaster();
    for (let i = 0; i < 275; i++) {
      const t = (i * 60) / 110;
      f.push(t, 5.5 + noise(i));
      expect(f.update(t, 5)).toBeNull();
    }
  });

  it("warns before a tiring rescuer drops below 5 cm", () => {
    const f = new SwapForecaster();
    let first: number | null = null;
    for (let i = 0; i < 275; i++) {
      const t = (i * 60) / 110;
      f.push(t, 5.7 - (1.4 * t) / 150 + noise(i)); // crosses 5.0 cm at 75 s
      if (first === null && f.update(t, 5) !== null) first = t;
    }
    expect(first).not.toBeNull();
    expect(first!).toBeLessThan(75);
  });
});
