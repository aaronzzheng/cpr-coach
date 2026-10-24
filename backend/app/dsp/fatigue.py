"""Fatigue model: compares recent depth to a baseline early in the rescuer cycle, plus HR rise,
and recommends a swap at 2 minutes or on a sustained depth drop."""

from __future__ import annotations

from collections import deque
from dataclasses import dataclass

import numpy as np

from ..config import (
    FATIGUE_BASELINE_MIN_N,
    FATIGUE_BASELINE_WINDOW_S,
    FATIGUE_DROP_FULL,
    FATIGUE_HR_RISE_FULL,
    FATIGUE_RECENT_N,
    FATIGUE_SWAP_AFTER_S,
    FATIGUE_SWAP_DROP,
    FATIGUE_SWAP_HOLD_S,
    TARGETS,
)


def _clamp(x: float, lo: float = 0.0, hi: float = 1.0) -> float:
    return max(lo, min(hi, x))


@dataclass
class FatigueState:
    score: float = 0.0
    baseline_depth_cm: float | None = None
    recent_depth_cm: float | None = None
    depth_drop: float = 0.0
    swap_recommended: bool = False
    cycle_elapsed_s: float = 0.0


class FatigueModel:
    def __init__(self) -> None:
        self.cycle_start: float | None = None
        self.hr_at_start: float | None = None
        self.baseline: list[float] = []
        self.recent: deque[float] = deque(maxlen=FATIGUE_RECENT_N)
        self.drop_since: float | None = None
        self.state = FatigueState()

    def reset_cycle(self, t: float | None = None, hr: float | None = None) -> None:
        self.__init__()
        self.cycle_start = t
        self.hr_at_start = hr

    def add_compression(self, t: float, depth_cm: float | None) -> None:
        if self.cycle_start is None:
            self.cycle_start = t
        if depth_cm is None:
            return
        lo, hi = FATIGUE_BASELINE_WINDOW_S
        if lo <= t - self.cycle_start <= hi:
            self.baseline.append(depth_cm)
        self.recent.append(depth_cm)

    def update(self, now: float, hr: float | None = None) -> FatigueState:
        if self.cycle_start is None:
            self.state = FatigueState()
            return self.state
        if self.hr_at_start is None and hr is not None:
            self.hr_at_start = hr
        elapsed = now - self.cycle_start
        s = FatigueState(cycle_elapsed_s=elapsed)

        if len(self.baseline) >= FATIGUE_BASELINE_MIN_N:
            s.baseline_depth_cm = float(np.median(self.baseline))
        if self.recent:
            s.recent_depth_cm = float(np.median(self.recent))
        if s.baseline_depth_cm and s.recent_depth_cm is not None and elapsed > FATIGUE_BASELINE_WINDOW_S[1]:
            s.depth_drop = 1.0 - s.recent_depth_cm / s.baseline_depth_cm

        hr_rise = (hr - self.hr_at_start) if (hr is not None and self.hr_at_start is not None) else 0.0
        s.score = _clamp(
            0.7 * _clamp(s.depth_drop / FATIGUE_DROP_FULL) + 0.3 * _clamp(hr_rise / FATIGUE_HR_RISE_FULL)
        )

        if elapsed >= FATIGUE_SWAP_AFTER_S and s.depth_drop >= FATIGUE_SWAP_DROP:
            if self.drop_since is None:
                self.drop_since = now
        else:
            self.drop_since = None
        sustained = self.drop_since is not None and now - self.drop_since >= FATIGUE_SWAP_HOLD_S
        s.swap_recommended = elapsed >= TARGETS["rescuer_swap_s"] or sustained
        self.state = s
        return s
