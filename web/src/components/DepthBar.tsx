// Depth parameter block (depth cyan). The bar fills downward like the chest, with the 5–6 cm band.
// Camera estimates are prefixed "~".
import { TARGETS } from "../config";
import type { Source } from "../fusion/fuse";

const MAX_CM = 8;
const pct = (cm: number) => `${(Math.min(MAX_CM, Math.max(0, cm)) / MAX_CM) * 100}%`;

export function DepthBar({ cm, estimate, source }: { cm: number | null; estimate: boolean; source: Source }) {
  const state = cm === null ? "none" : cm < TARGETS.depth_min_cm ? "low" : cm > TARGETS.depth_max_cm ? "high" : "ok";
  const hint = state === "low" ? "Deeper" : state === "high" ? "Lighter" : null;
  return (
    <section className="param param-depth" aria-label="Compression depth">
      <header className="param-head">
        <span className="param-name">Depth</span>
        <span className="param-meta">{source ? `via ${source}${estimate ? ", estimated" : ""}` : "no signal"}</span>
      </header>
      <div className="depth-layout">
        <div className="param-body">
          <span className={`param-value ${state}`}>{cm === null ? "—" : `${estimate ? "~" : ""}${cm.toFixed(1)}`}</span>
          <span className="param-unit">cm</span>
          {hint && <span className="param-hint">{hint}</span>}
        </div>
        <div className="depth-column" aria-hidden="true">
          <div className="depth-band" style={{ top: pct(TARGETS.depth_min_cm), height: pct(TARGETS.depth_max_cm - TARGETS.depth_min_cm) }} />
          {cm !== null && <div className={`depth-fill ${state}`} style={{ height: pct(cm) }} />}
          <span className="depth-tick" style={{ top: pct(TARGETS.depth_min_cm) }}>
            {TARGETS.depth_min_cm}
          </span>
          <span className="depth-tick" style={{ top: pct(TARGETS.depth_max_cm) }}>
            {TARGETS.depth_max_cm}
          </span>
        </div>
      </div>
      <footer className="param-foot">
        <span>
          Target {TARGETS.depth_min_cm}–{TARGETS.depth_max_cm} cm
        </span>
      </footer>
    </section>
  );
}
