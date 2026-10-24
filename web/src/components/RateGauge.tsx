// Rate parameter block, monitor-style: identity colour (trace green), big condensed numeral,
// and a slim scale with the 100–120 target band. Out of range, the numeral inverts to alarm amber.
import { TARGETS } from "../config";
import type { Source } from "../fusion/fuse";

const SCALE_MIN = 80;
const SCALE_MAX = 140;
const pos = (v: number) => `${((Math.min(SCALE_MAX, Math.max(SCALE_MIN, v)) - SCALE_MIN) / (SCALE_MAX - SCALE_MIN)) * 100}%`;

export function RateGauge({ cpm, source }: { cpm: number | null; source: Source }) {
  const state = cpm === null ? "none" : cpm < TARGETS.rate_min_cpm ? "low" : cpm > TARGETS.rate_max_cpm ? "high" : "ok";
  const hint = state === "low" ? "Faster" : state === "high" ? "Slower" : null;
  return (
    <section className="param param-rate" aria-label="Compression rate">
      <header className="param-head">
        <span className="param-name">Rate</span>
        <span className="param-meta">{source ? `via ${source}` : "no signal"}</span>
      </header>
      <div className="param-body">
        <span className={`param-value ${state}`}>{cpm === null ? "—" : Math.round(cpm)}</span>
        <span className="param-unit">/min</span>
        {hint && <span className="param-hint">{hint}</span>}
      </div>
      <div className="scale" aria-hidden="true">
        <div className="scale-band" style={{ left: pos(TARGETS.rate_min_cpm), right: `calc(100% - ${pos(TARGETS.rate_max_cpm)})` }} />
        {cpm !== null && <div className="scale-mark" style={{ left: pos(cpm) }} />}
      </div>
      <footer className="param-foot">
        <span>{SCALE_MIN}</span>
        <span>
          Target {TARGETS.rate_min_cpm}–{TARGETS.rate_max_cpm}
        </span>
        <span>{SCALE_MAX}</span>
      </footer>
    </section>
  );
}
