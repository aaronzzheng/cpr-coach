// Home: one clear primary action (start a session), session options, calibration status, and
// the leaderboard.
import { BadgeCheck, Gauge, Mic, Play, SlidersHorizontal, Wind } from "lucide-react";
import { t } from "../i18n";
import type { Calibration, LeaderboardEntry } from "../net/api";
import type { Patient } from "../patient";
import { Leaderboard } from "./Leaderboard";

interface Props {
  name: string;
  onName: (n: string) => void;
  onStart: () => void;
  onSkills: () => void;
  onCalibrate: () => void;
  patient: Patient;
  onPatient: (p: Patient) => void;
  breaths: boolean;
  onBreaths: (on: boolean) => void;
  handsFree: boolean;
  onHandsFree: (on: boolean) => void;
  voiceSupported: boolean;
  board: LeaderboardEntry[];
  calibration: Calibration | null;
  error: string | null;
}

const PATIENTS: [Patient, string][] = [
  ["adult", "Adult"],
  ["child", "Child"],
  ["infant", "Infant"],
];

export function HomePanel(p: Props) {
  return (
    <div className="home">
      <section className="card start-card">
        <h2 className="title-lg">{t("Who's practicing?")}</h2>
        <p className="lede">{t("Kneel beside the manikin, side-on to the camera, with the watch on your wrist.")}</p>
        <label className="sr-only" htmlFor="rescuer">
          {t("Name")}
        </label>
        <input
          id="rescuer"
          className="field"
          value={p.name}
          maxLength={40}
          placeholder={t("Your name")}
          autoComplete="off"
          onChange={(e) => p.onName(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter") p.onStart();
          }}
        />
        <div className="options">
          <div className="segmented" role="group" aria-label={t("Patient")}>
            {PATIENTS.map(([id, label]) => (
              <button key={id} aria-pressed={p.patient === id} onClick={() => p.onPatient(id)}>
                {t(label)}
              </button>
            ))}
          </div>
          <button className="toggle-pill" aria-pressed={p.breaths} onClick={() => p.onBreaths(!p.breaths)}>
            <Wind size={16} aria-hidden="true" />
            {t("30:2 breaths")}
          </button>
          {p.voiceSupported && (
            <button className="toggle-pill" aria-pressed={p.handsFree} onClick={() => p.onHandsFree(!p.handsFree)}>
              <Mic size={16} aria-hidden="true" />
              {t("Hands-free")}
            </button>
          )}
        </div>
        {p.handsFree && p.voiceSupported && (
          <p className="meta">{t("Say \"swap\", \"how long\", \"how am I doing\" or \"stop\" while you work.")}</p>
        )}
        <div className="actions">
          <button className="btn primary lg grow" onClick={p.onStart}>
            <Play size={20} fill="currentColor" aria-hidden="true" />
            {t("Start session")}
          </button>
          <button className="btn secondary lg" onClick={p.onSkills} title={t("A timed 2-minute test, pass or fail")}>
            <BadgeCheck size={20} aria-hidden="true" />
            {t("Skills check")}
          </button>
          <button className="btn secondary lg" onClick={p.onCalibrate}>
            <SlidersHorizontal size={20} aria-hidden="true" />
            {t("Calibrate")}
          </button>
        </div>
        <p className="meta">
          <Gauge size={16} aria-hidden="true" />
          {p.calibration
            ? t("Watch depth ×%@ · Camera depth %@", p.calibration.depth_scale.toFixed(2), p.calibration.cm_per_px ? t("calibrated") : t("estimated"))
            : t("Can't reach the backend. Run make dev or make demo.")}
        </p>
        {p.error && <p className="error">{p.error}</p>}
      </section>
      <section className="card board-card">
        <header className="card-head">
          <h2 className="title-md">{t("Leaderboard")}</h2>
          <span className="meta">{t("Top 10")}</span>
        </header>
        <Leaderboard entries={p.board} />
      </section>
    </div>
  );
}
