// Backend → dashboard message types (PRD §7.3), mirroring backend/app/models.py.

export interface StateMsg {
  type: "state";
  ts: number;
  session: {
    id: string;
    status: "idle" | "running" | "summary";
    elapsed_s: number;
    cycle_elapsed_s: number;
    name: string;
  };
  sources: {
    phone_connected: boolean;
    watch_streaming: boolean;
    packet_rate_hz: number;
    gaps: number;
    last_packet_age_ms: number | null;
    watch_reachable: boolean | null;
    source: "watch" | "sim" | "replay" | "none";
  };
  hr: { bpm: number | null; age_s: number | null };
  compressions: {
    count: number;
    rate_cpm: number | null;
    last_depth_cm: number | null;
    depth_avg5_cm: number | null;
    last_t: number | null;
  };
  pauses: {
    count: number;
    longest_s: number;
    hands_off_s: number;
    ccf: number | null;
    in_pause: boolean;
    pause_elapsed_s: number;
  };
  fatigue: {
    score: number;
    baseline_depth_cm: number | null;
    recent_depth_cm: number | null;
    swap_recommended: boolean;
  };
  wave: { t0: number; fs: number; a_up: number[] };
}

export interface CompressionMsg {
  type: "compression";
  t: number;
  interval_s: number | null;
  inst_rate_cpm: number | null;
  depth_cm: number | null;
  rate_ok: boolean;
  depth_ok: boolean | null;
}

export type ServerMsg = StateMsg | CompressionMsg;

export type ClientCmd =
  | { cmd: "start"; name: string }
  | { cmd: "stop" }
  | { cmd: "swap" }
  | { cmd: "metronome"; on: boolean; bpm: number };
