// REST calls to the backend: session lifecycle, summary, leaderboard, calibration.
import type { CameraMetrics } from "../session/sessionTracker";

export interface Summary {
  session_id: string;
  name: string;
  date: string;
  source: "watch" | "camera";
  score: number;
  grade: string;
  compressions: number;
  elapsed_s: number | null;
  rate_pct: number | null;
  depth_pct: number | null;
  depth_estimated: boolean;
  ccf: number | null;
  pauses: number;
  longest_pause_s: number;
  avg_rate_cpm: number | null;
  avg_depth_cm: number | null;
  elbow_pct: number | null;
  align_pct: number | null;
  depth_series: [number, number][];
  fatigue_at_s: number | null;
}

export interface LeaderboardEntry {
  session_id: string;
  name: string;
  score: number;
  grade: string;
  date: string;
}

export interface Calibration {
  depth_scale: number;
  cm_per_px: number | null;
}

async function call<T>(method: "GET" | "POST", path: string, body?: unknown): Promise<T> {
  const r = await fetch(path, {
    method,
    headers: body === undefined ? undefined : { "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  if (!r.ok) {
    const detail = await r.json().then((j: { detail?: string }) => j.detail).catch(() => undefined);
    throw new Error(detail ?? `${method} ${path} → ${r.status}`);
  }
  return (await r.json()) as T;
}

export const api = {
  startSession: (name: string, patient = "adult") => call<{ session_id: string }>("POST", "/api/session/start", { name, patient }),
  stopSession: () => call<{ session_id: string }>("POST", "/api/session/stop"),
  postSummary: (id: string, cam: CameraMetrics) => call<Summary>("POST", `/api/session/${id}/summary`, cam),
  leaderboard: () => call<LeaderboardEntry[]>("GET", "/api/leaderboard"),
  addToLeaderboard: (session_id: string) => call<LeaderboardEntry[]>("POST", "/api/leaderboard", { session_id }),
  calibration: () => call<Calibration>("GET", "/api/calibration"),
  saveCalibration: (c: Partial<Calibration>) => call<Calibration>("POST", "/api/calibration", c),
};
