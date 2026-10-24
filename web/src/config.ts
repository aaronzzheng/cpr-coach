// Shared thresholds: AHA targets come from shared/targets.json so backend and frontend agree.
import targetsJson from "../../shared/targets.json";

export interface Targets {
  rate_min_cpm: number;
  rate_max_cpm: number;
  rate_target_cpm: number;
  depth_min_cm: number;
  depth_max_cm: number;
  pause_threshold_s: number;
  max_hands_off_s: number;
  ccf_target: number;
  rescuer_swap_s: number;
  elbow_locked_min_deg: number;
  shoulder_over_hands_max_deg: number;
}

export const TARGETS: Targets = targetsJson;

export const HEALTH_POLL_MS = 2000;
