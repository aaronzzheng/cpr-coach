// Home: one clear primary action (start a session), calibration status, and the leaderboard.
import { Gauge, Play, SlidersHorizontal } from "lucide-react";
import type { Calibration, LeaderboardEntry } from "../net/api";
import { Leaderboard } from "./Leaderboard";

interface Props {
  name: string;
  onName: (n: string) => void;
  onStart: () => void;
  onCalibrate: () => void;
  board: LeaderboardEntry[];
  calibration: Calibration | null;
  error: string | null;
}

export function HomePanel({ name, onName, onStart, onCalibrate, board, calibration, error }: Props) {
  return (
    <div className="home">
      <section className="card start-card">
        <h2 className="title-lg">Who's practicing?</h2>
        <p className="lede">Kneel beside the manikin, side-on to the camera, with the watch on your wrist.</p>
        <label className="sr-only" htmlFor="rescuer">
          Name
        </label>
        <input
          id="rescuer"
          className="field"
          value={name}
          maxLength={40}
          placeholder="Your name"
          autoComplete="off"
          onChange={(e) => onName(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter") onStart();
          }}
        />
        <div className="actions">
          <button className="btn primary lg grow" onClick={onStart}>
            <Play size={20} fill="currentColor" aria-hidden="true" />
            Start session
          </button>
          <button className="btn secondary lg" onClick={onCalibrate}>
            <SlidersHorizontal size={20} aria-hidden="true" />
            Calibrate
          </button>
        </div>
        <p className="meta">
          <Gauge size={16} aria-hidden="true" />
          {calibration
            ? `Watch depth ×${calibration.depth_scale.toFixed(2)} · Camera depth ${calibration.cm_per_px ? "calibrated" : "estimated"}`
            : "Can't reach the backend. Run make dev or make demo."}
        </p>
        {error && <p className="error">{error}</p>}
      </section>
      <section className="card board-card">
        <header className="card-head">
          <h2 className="title-md">Leaderboard</h2>
          <span className="meta">Top 10</span>
        </header>
        <Leaderboard entries={board} />
      </section>
    </div>
  );
}
