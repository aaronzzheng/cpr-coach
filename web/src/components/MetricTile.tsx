// Stat tile for a live measurement: label, large value (system sans, white — never the data
// colour), a status chip that pairs icon + words, and a meter whose fill carries the status.
import { CircleCheck, TriangleAlert } from "lucide-react";
import type { Source } from "../fusion/fuse";
import { num, t } from "../i18n";

export interface MetricTileProps {
  label: string;
  value: number | null;
  digits?: number;
  unit: string;
  scale: [number, number];
  target: [number, number];
  /** Words for the out-of-range states, e.g. ["Too slow", "Too fast"]. */
  outWords: [string, string];
  source: Source;
  estimate?: boolean;
  /** Slack around the target band before a value counts as out of range. */
  tolerance?: number;
}

export function MetricTile({ label, value, digits = 0, unit, scale, target, outWords, source, estimate = false, tolerance = 0 }: MetricTileProps) {
  const [lo, hi] = scale;
  const pos = (v: number) => (Math.min(hi, Math.max(lo, v)) - lo) / (hi - lo);
  const state = value === null ? "none" : value < target[0] - tolerance ? "low" : value > target[1] + tolerance ? "high" : "ok";
  const chip =
    state === "ok" ? { cls: "good", text: t("On target"), Icon: CircleCheck } :
    state === "low" ? { cls: "warn", text: outWords[0], Icon: TriangleAlert } :
    state === "high" ? { cls: "warn", text: outWords[1], Icon: TriangleAlert } : null;
  const shown = value === null ? "—" : `${estimate ? "≈" : ""}${num(value, digits)}`;

  return (
    <section className="tile" aria-label={label}>
      <header className="tile-head">
        <h2 className="tile-label">{label}</h2>
        {chip && (
          <span className={`chip ${chip.cls}`}>
            <chip.Icon size={16} strokeWidth={2.25} aria-hidden="true" />
            {chip.text}
          </span>
        )}
      </header>
      <p className="tile-value">
        <span className="tile-reading">
          <span className={value === null ? "tile-number empty" : "tile-number"}>{shown}</span>
          <span className="tile-unit">{unit}</span>
        </span>
      </p>
      <div className="meter" role="meter" aria-valuemin={lo} aria-valuemax={hi} aria-valuenow={value ?? undefined} aria-label={label}>
        <div className="meter-target" style={{ left: `${pos(target[0]) * 100}%`, width: `${(pos(target[1]) - pos(target[0])) * 100}%` }} />
        {value !== null && (
          <>
            <div className={`meter-fill ${state}`} style={{ width: `${pos(value) * 100}%` }} />
            <div className={`meter-dot ${state}`} style={{ left: `${pos(value) * 100}%` }} />
          </>
        )}
      </div>
      <footer className="tile-foot">
        <span>{t("Target %@", `${target[0]}–${target[1]}`)}</span>
        <span>{source ? (estimate ? t("Camera estimate") : t(source === "watch" ? "Watch" : "Camera")) : t("No data yet")}</span>
      </footer>
    </section>
  );
}
