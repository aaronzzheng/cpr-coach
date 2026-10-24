// Vertical depth bar (0–8 cm) with the AHA 5–6 cm band. Camera estimates are marked with "~".
import { TARGETS } from "../config";
import type { Source } from "../fusion/fuse";

const MAX_CM = 8;
const pct = (cm: number) => `${(Math.min(MAX_CM, Math.max(0, cm)) / MAX_CM) * 100}%`;

export function DepthBar({ cm, estimate, source }: { cm: number | null; estimate: boolean; source: Source }) {
  const ok = cm !== null && cm >= TARGETS.depth_min_cm && cm <= TARGETS.depth_max_cm;
  const cls = cm === null ? "" : ok ? "good" : "bad";
  return (
    <div className="metric">
      <div className="metric-label">DEPTH</div>
      <div className="depth">
        <div className="depth-bar">
          <div
            className="depth-band"
            style={{ bottom: pct(TARGETS.depth_min_cm), height: `${((TARGETS.depth_max_cm - TARGETS.depth_min_cm) / MAX_CM) * 100}%` }}
          />
          {cm !== null && <div className={`depth-fill ${cls}`} style={{ height: pct(cm) }} />}
          <span className="depth-tick" style={{ bottom: pct(TARGETS.depth_max_cm) }}>
            {TARGETS.depth_max_cm.toFixed(1)}
          </span>
          <span className="depth-tick" style={{ bottom: pct(TARGETS.depth_min_cm) }}>
            {TARGETS.depth_min_cm.toFixed(1)}
          </span>
        </div>
        <div className={`depth-value ${cls}`}>
          {cm === null ? "—" : `${estimate ? "~" : ""}${cm.toFixed(1)}`}
          <span className="depth-unit"> cm</span>
        </div>
      </div>
      <div className="metric-source">{source ? `via ${source}${estimate ? " (estimate)" : ""}` : "no signal"}</div>
    </div>
  );
}
