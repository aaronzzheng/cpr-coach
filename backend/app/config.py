"""Configuration: loads shared/targets.json (AHA targets) and environment settings."""

from __future__ import annotations

import json
import os
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
TARGETS_PATH = REPO_ROOT / "shared" / "targets.json"
DATA_DIR = Path(os.environ.get("CPR_DATA_DIR", REPO_ROOT / "data"))
WEB_DIST = REPO_ROOT / "web" / "dist"


def load_targets() -> dict[str, float]:
    with TARGETS_PATH.open() as f:
        return json.load(f)


TARGETS = load_targets()

# Watch DSP tunables (PRD §6.3). Prominence needs tuning on real data.
G0 = 9.80665
IMU_FS = 100.0
BANDPASS_HZ = (0.5, 5.0)
BANDPASS_ORDER = 2
PEAK_DISTANCE_S = 0.3
PEAK_PROMINENCE = float(os.environ.get("CPR_PEAK_PROMINENCE", "3.0"))
PEAK_COMMIT_AGE_S = 0.25
PEAK_BUFFER_S = 4.0
MAX_INTERVAL_S = 2.0
RATE_WINDOW = 5
DEPTH_WINDOW = 8
CYCLE_MIN_S = 0.25
CYCLE_MAX_S = 1.5

# Fatigue model (PRD §6.3 step 7).
FATIGUE_BASELINE_WINDOW_S = (10.0, 40.0)
FATIGUE_BASELINE_MIN_N = 10
FATIGUE_RECENT_N = 15
FATIGUE_DROP_FULL = 0.25
FATIGUE_HR_RISE_FULL = 30.0
FATIGUE_SWAP_DROP = 0.15
FATIGUE_SWAP_HOLD_S = 10.0
FATIGUE_SWAP_AFTER_S = 60.0
FATIGUE_RESET_PAUSE_S = 5.0

# Session and broadcast.
SESSION_CLOCK_GRACE_S = 5.0
BROADCAST_HZ = 20.0
WAVE_S = 6.0
WAVE_FS = 50.0
SOURCE_STALE_S = 1.0
# Watch→laptop clock offset: minimum over this many recent packets (least transport latency).
CLOCK_OFFSET_WINDOW = 50
# A forward jump this large in watch timestamps means a different sender/clock: re-learn the offset.
CLOCK_JUMP_S = 5.0
# The summary uses watch metrics only if the watch saw at least this many compressions.
MIN_WATCH_COMPRESSIONS = 10
LEADERBOARD_SIZE = 10
DEPTH_SCALE_RANGE = (0.5, 2.0)

# Depth targets by patient (AHA: about 5 cm adult and child, 4 cm infant); rate is the same.
PATIENT_DEPTH_CM: dict[str, tuple[float, float]] = {
    "adult": (TARGETS["depth_min_cm"], TARGETS["depth_max_cm"]),
    "child": (4.5, 5.5),
    "infant": (3.5, 4.5),
}
# Depth within this of the band counts as on target (about the measurement error).
DEPTH_TOLERANCE_CM = 0.3
