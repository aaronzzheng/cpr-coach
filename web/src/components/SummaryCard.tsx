// End-of-session sheet: the score as the single hero figure, then the breakdown as a calm grid
// (icon + words for each pass/fail), the depth trace against the target band, and two actions.
import { CircleCheck, RotateCcw, Trophy, TriangleAlert } from "lucide-react";
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
  const Icon = good === true ? CircleCheck : good === false ? TriangleAlert : null;
  return (
    <div className={`stat ${good === true ? "good" : good === false ? "warn" : ""}`}>
      <span className="stat-label">{label}</span>
      <span className="stat-value">
        {Icon && <Icon size={18} strokeWidth={2.25} aria-hidden="true" />}
        {value}
      </span>
    </div>
  );
}

export function SummaryCard({ summary: s, error, added, onAdd, onAgain }: Props) {
  return (
    <div className="overlay" role="dialog" aria-modal="true" aria-label="Session summary">
      <div className="sheet">
        {!s && !error && <p className="sheet-loading">Scoring…</p>}
        {error && (
          <>
            <p className="error">Couldn't score this session: {error}</p>
            <div className="actions end">
              <button className="btn primary lg" onClick={onAgain}>
                Back
              </button>
            </div>
          </>
        )}
        {s && (
          <>
            <header className="sheet-head">
              <div>
                <p className="eyebrow-name">{s.name}</p>
                <p className="score">
                  {Math.round(s.score)}
                  <span className="score-of">/100</span>
                </p>
                <p className="lede">
                  {s.compressions} compressions in {s.elapsed_s !== null ? formatClock(s.elapsed_s) : "—"}, measured by the {s.source}
                </p>
              </div>
              <span className={`grade-badge g${s.grade}`} aria-label={`Grade ${s.grade}`}>
                {s.grade}
              </span>
            </header>
            <div className="stats">
              <Stat label="Rate in range" value={pct(s.rate_pct)} good={s.rate_pct === null ? null : s.rate_pct >= 0.8} />
              <Stat label={s.depth_estimated ? "Depth in range (est.)" : "Depth in range"} value={pct(s.depth_pct)} good={s.depth_pct === null ? null : s.depth_pct >= 0.8} />
              <Stat label="Hands on chest" value={pct(s.ccf)} good={s.ccf === null ? null : s.ccf >= 0.8} />
              <Stat label="Pauses" value={s.pauses ? `${s.pauses} · longest ${s.longest_pause_s.toFixed(1)} s` : "None"} good={s.pauses === 0} />
              <Stat label="Average rate" value={s.avg_rate_cpm === null ? "—" : `${Math.round(s.avg_rate_cpm)} /min`} />
              <Stat label="Average depth" value={s.avg_depth_cm === null ? "—" : `${s.depth_estimated ? "≈" : ""}${s.avg_depth_cm.toFixed(1)} cm`} />
              <Stat label="Elbows locked" value={pct(s.elbow_pct)} good={s.elbow_pct === null ? null : s.elbow_pct >= 0.8} />
              <Stat label="Shoulders over hands" value={pct(s.align_pct)} good={s.align_pct === null ? null : s.align_pct >= 0.8} />
            </div>
            <section className="chart-card" aria-label="Depth over time">
              <header className="card-head">
                <h3 className="title-sm">Depth over time</h3>
                <span className="meta">Shaded band: 5–6 cm target</span>
              </header>
              <DepthChart series={s.depth_series} fatigueAt={s.fatigue_at_s} />
            </section>
            <div className="actions end">
              <button className="btn secondary lg" onClick={onAgain}>
                <RotateCcw size={18} aria-hidden="true" />
                Try again
              </button>
              <button className="btn primary lg" disabled={added} onClick={onAdd}>
                <Trophy size={18} aria-hidden="true" />
                {added ? "Saved" : "Save to leaderboard"}
              </button>
            </div>
          </>
        )}
      </div>
    </div>
  );
}
