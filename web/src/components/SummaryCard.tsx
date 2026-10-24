// End-of-session scorecard: score and grade, per-metric percentages, depth chart, actions.
import type { Summary } from "../net/api";
import { DepthChart } from "./DepthChart";
import { formatClock } from "./Timer";

interface Props {
  summary: Summary | null;
  error: string | null;
  added: boolean;
  onAdd: () => void;
  onAgain: () => void;
}

const pct = (x: number | null) => (x === null ? "—" : `${Math.round(x * 100)}%`);

function Stat({ label, value, good }: { label: string; value: string; good?: boolean | null }) {
  return (
    <div className={`stat ${good === true ? "good" : good === false ? "bad" : ""}`}>
      <div className="stat-value">{value}</div>
      <div className="stat-label">{label}</div>
    </div>
  );
}

export function SummaryCard({ summary: s, error, added, onAdd, onAgain }: Props) {
  return (
    <div className="overlay">
      <div className="summary">
        {!s && !error && <div className="summary-loading">Scoring…</div>}
        {error && (
          <>
            <div className="error">Couldn't score this session: {error}</div>
            <div className="summary-actions">
              <button className="btn primary" onClick={onAgain}>
                Back
              </button>
            </div>
          </>
        )}
        {s && (
          <>
            <div className="summary-head">
              <div className={`grade grade-${s.grade}`}>{s.grade}</div>
              <div>
                <div className="summary-score">
                  {Math.round(s.score)}
                  <span>/100</span>
                </div>
                <div className="summary-name">
                  {s.name} · {s.elapsed_s !== null ? formatClock(s.elapsed_s) : "—"} · {s.compressions} compressions · via{" "}
                  {s.source}
                </div>
              </div>
            </div>
            <div className="stats">
              <Stat label="Rate in range" value={pct(s.rate_pct)} good={s.rate_pct === null ? null : s.rate_pct >= 0.8} />
              <Stat
                label={`Depth in range${s.depth_estimated ? " (est.)" : ""}`}
                value={pct(s.depth_pct)}
                good={s.depth_pct === null ? null : s.depth_pct >= 0.8}
              />
              <Stat label="Hands on chest" value={pct(s.ccf)} good={s.ccf === null ? null : s.ccf >= 0.8} />
              <Stat label="Elbows locked" value={pct(s.elbow_pct)} good={s.elbow_pct === null ? null : s.elbow_pct >= 0.8} />
              <Stat label="Shoulders over hands" value={pct(s.align_pct)} good={s.align_pct === null ? null : s.align_pct >= 0.8} />
              <Stat label="Avg rate" value={s.avg_rate_cpm === null ? "—" : `${Math.round(s.avg_rate_cpm)}/min`} />
              <Stat
                label="Avg depth"
                value={s.avg_depth_cm === null ? "—" : `${s.depth_estimated ? "~" : ""}${s.avg_depth_cm.toFixed(1)} cm`}
              />
              <Stat
                label="Pauses"
                value={s.pauses ? `${s.pauses} (max ${s.longest_pause_s.toFixed(1)} s)` : "0"}
                good={s.pauses === 0}
              />
            </div>
            <DepthChart series={s.depth_series} fatigueAt={s.fatigue_at_s} />
            <div className="summary-actions">
              <button className="btn primary" disabled={added} onClick={onAdd}>
                {added ? "Added ✓" : "Add to leaderboard"}
              </button>
              <button className="btn" onClick={onAgain}>
                Try again
              </button>
            </div>
          </>
        )}
      </div>
    </div>
  );
}
