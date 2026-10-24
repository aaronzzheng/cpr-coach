// End-of-session sheet: the score as the single hero figure, then the breakdown as a calm grid
// (icon + words for each pass/fail), the depth trace against the target band, and two actions.
import { CircleCheck, ClipboardList, RotateCcw, Trophy, TriangleAlert } from "lucide-react";
import { t } from "../i18n";
import type { Summary } from "../net/api";
import { depthMax, depthMin } from "../patient";
import { DepthChart } from "./DepthChart";
import { SkillsResult } from "./SkillsResult";
import { formatClock } from "./Timer";

interface Props {
  summary: Summary | null;
  error: string | null;
  added: boolean;
  onAdd: () => void;
  onAgain: () => void;
  /** The session was a 2-minute skills check. */
  skills: boolean;
  onHandoff: () => void;
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

export function SummaryCard({ summary: s, error, added, onAdd, onAgain, skills, onHandoff }: Props) {
  return (
    <div className="overlay" role="dialog" aria-modal="true" aria-label={t("Session summary")}>
      <div className="sheet">
        {!s && !error && <p className="sheet-loading">{t("Scoring…")}</p>}
        {error && (
          <>
            <p className="error">{t("Couldn't score this session: %@", error)}</p>
            <div className="actions end">
              <button className="btn primary lg" onClick={onAgain}>
                {t("Back")}
              </button>
            </div>
          </>
        )}
        {s && (
          <>
            {skills && <SkillsResult summary={s} />}
            <header className="sheet-head">
              <div>
                <p className="eyebrow-name">{s.name}</p>
                <p className="score">
                  {Math.round(s.score)}
                  <span className="score-of">/100</span>
                </p>
                <p className="lede">
                  {t("%@ compressions in %@", s.compressions, s.elapsed_s !== null ? formatClock(s.elapsed_s) : "—")} · {t(s.source === "watch" ? "Watch" : "Camera")}
                </p>
              </div>
              <span className={`grade-badge g${s.grade}`} aria-label={t("Grade %@", s.grade)}>
                {s.grade}
              </span>
            </header>
            <div className="stats">
              <Stat label={t("Rate in range")} value={pct(s.rate_pct)} good={s.rate_pct === null ? null : s.rate_pct >= 0.8} />
              <Stat label={s.depth_estimated ? t("Depth in range (est.)") : t("Depth in range")} value={pct(s.depth_pct)} good={s.depth_pct === null ? null : s.depth_pct >= 0.8} />
              <Stat label={t("Hands on chest")} value={pct(s.ccf)} good={s.ccf === null ? null : s.ccf >= 0.8} />
              <Stat label={t("Pauses")} value={s.pauses ? t("%@ · longest %@ s", s.pauses, s.longest_pause_s.toFixed(1)) : t("None")} good={s.pauses === 0} />
              <Stat label={t("Average rate")} value={s.avg_rate_cpm === null ? "—" : `${Math.round(s.avg_rate_cpm)} ${t("/min")}`} />
              <Stat label={t("Average depth")} value={s.avg_depth_cm === null ? "—" : `${s.depth_estimated ? "≈" : ""}${s.avg_depth_cm.toFixed(1)} cm`} />
              <Stat label={t("Elbows locked")} value={pct(s.elbow_pct)} good={s.elbow_pct === null ? null : s.elbow_pct >= 0.8} />
              <Stat label={t("Shoulders over hands")} value={pct(s.align_pct)} good={s.align_pct === null ? null : s.align_pct >= 0.8} />
            </div>
            <section className="chart-card" aria-label={t("Depth over time")}>
              <header className="card-head">
                <h3 className="title-sm">{t("Depth over time")}</h3>
                <span className="meta">{t("Shaded band: %@ cm target", `${depthMin()}–${depthMax()}`)}</span>
              </header>
              <DepthChart series={s.depth_series} fatigueAt={s.fatigue_at_s} />
            </section>
            <div className="actions end">
              <button className="btn secondary lg" onClick={onHandoff}>
                <ClipboardList size={18} aria-hidden="true" />
                {t("Report for paramedics")}
              </button>
              <button className="btn secondary lg" onClick={onAgain}>
                <RotateCcw size={18} aria-hidden="true" />
                {t("Try again")}
              </button>
              <button className="btn primary lg" disabled={added} onClick={onAdd}>
                <Trophy size={18} aria-hidden="true" />
                {added ? t("Saved") : t("Save to leaderboard")}
              </button>
            </div>
          </>
        )}
      </div>
    </div>
  );
}
