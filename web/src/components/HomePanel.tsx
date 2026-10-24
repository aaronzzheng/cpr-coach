// Home: who's doing CPR, start, calibrate, and the leaderboard.
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
    <div className="panel home">
      <label className="home-label" htmlFor="rescuer">
        Who's doing CPR?
      </label>
      <input
        id="rescuer"
        className="home-name"
        value={name}
        maxLength={40}
        placeholder="Name"
        autoComplete="off"
        onChange={(e) => onName(e.target.value)}
        onKeyDown={(e) => {
          if (e.key === "Enter") onStart();
        }}
      />
      <div className="home-actions">
        <button className="btn primary" onClick={onStart}>
          Start
        </button>
        <button className="btn" onClick={onCalibrate}>
          Calibrate
        </button>
      </div>
      <div className="home-cal">
        {calibration
          ? `Calibration: watch ×${calibration.depth_scale.toFixed(2)} · camera ${
              calibration.cm_per_px ? `${calibration.cm_per_px.toFixed(3)} cm/px` : "not calibrated (estimating)"
            }`
          : "Calibration: backend offline"}
      </div>
      {error && <div className="error">{error}</div>}
      <h2 className="panel-title">Leaderboard</h2>
      <Leaderboard entries={board} />
    </div>
  );
}
