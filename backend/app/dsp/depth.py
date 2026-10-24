"""Per-cycle depth: double integration of raw a_up between two compression tops,
with linear detrending so velocity is zero at both tops and displacement returns to start."""

from __future__ import annotations

import numpy as np
from scipy.integrate import cumulative_trapezoid

from ..config import CYCLE_MAX_S, CYCLE_MIN_S


def _detrend_endpoints(t: np.ndarray, y: np.ndarray) -> np.ndarray:
    """Subtract the straight line through the first and last points."""
    span = t[-1] - t[0]
    return y - (y[0] + (y[-1] - y[0]) * (t - t[0]) / span)


def cycle_depth_cm(t: np.ndarray, a_up: np.ndarray, scale: float = 1.0) -> float | None:
    """`t` (s) and raw `a_up` (m/s²) covering one cycle top→top. None if the cycle is implausible."""
    if len(t) < 3:
        return None
    dur = t[-1] - t[0]
    if dur < CYCLE_MIN_S or dur > CYCLE_MAX_S:
        return None
    a = a_up - a_up.mean()
    v = _detrend_endpoints(t, cumulative_trapezoid(a, t, initial=0.0))
    x = _detrend_endpoints(t, cumulative_trapezoid(v, t, initial=0.0))
    return float((x.max() - x.min()) * 100.0 * scale)
