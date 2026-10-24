"""Online compression detection on band-passed a_up.

Bottoms of compressions are maxima of a_up, tops are minima. Peaks are found over a rolling
buffer each packet and committed once stable. Each bottom becomes a Compression; its depth is
filled in when the following top arrives (the cycle top→bottom→top is then complete).
"""

from __future__ import annotations

from collections import deque
from dataclasses import dataclass

import numpy as np
from scipy.signal import find_peaks

from ..config import (
    IMU_FS,
    MAX_INTERVAL_S,
    PEAK_BUFFER_S,
    PEAK_COMMIT_AGE_S,
    PEAK_DISTANCE_S,
    PEAK_PROMINENCE,
    RATE_WINDOW,
)
from .depth import cycle_depth_cm


@dataclass
class Compression:
    t: float
    interval_s: float | None
    inst_rate_cpm: float | None
    depth_cm: float | None = None


class CompressionDetector:
    def __init__(
        self,
        fs: float = IMU_FS,
        prominence: float = PEAK_PROMINENCE,
        depth_scale: float = 1.0,
    ) -> None:
        self.fs = fs
        self.prominence = prominence
        self.depth_scale = depth_scale
        n = int(PEAK_BUFFER_S * fs)
        self.t: deque[float] = deque(maxlen=n)
        self.raw: deque[float] = deque(maxlen=n)
        self.filt: deque[float] = deque(maxlen=n)
        self.discontinuities: list[float] = []
        self.last_bottom: float | None = None
        self.last_top: float | None = None
        self.prev_top: float | None = None
        self.pending: Compression | None = None
        self.intervals: deque[float] = deque(maxlen=RATE_WINDOW)
        self.count = 0

    @property
    def rate_cpm(self) -> float | None:
        return 60.0 / float(np.median(self.intervals)) if self.intervals else None

    def mark_discontinuity(self, t: float) -> None:
        self.discontinuities.append(t)

    def push(self, t: np.ndarray, raw: np.ndarray, filt: np.ndarray) -> tuple[list[Compression], list[Compression]]:
        """Add samples. Returns (new bottoms, completed compressions with depth resolved)."""
        self.t.extend(t.tolist())
        self.raw.extend(raw.tolist())
        self.filt.extend(filt.tolist())
        if self.t:
            self.discontinuities = [d for d in self.discontinuities if d >= self.t[0]]

        bottoms: list[Compression] = []
        done: list[Compression] = []
        if len(self.t) < 3:
            return bottoms, done

        ts = np.fromiter(self.t, float)
        f = np.fromiter(self.filt, float)
        now = ts[-1]
        dist = max(1, int(PEAK_DISTANCE_S * self.fs))

        events: list[tuple[float, str]] = []
        for kind, sig in (("bottom", f), ("top", -f)):
            idx, _ = find_peaks(sig, distance=dist, prominence=self.prominence)
            last = self.last_bottom if kind == "bottom" else self.last_top
            for i in idx:
                pt = ts[i]
                if now - pt < PEAK_COMMIT_AGE_S:
                    continue
                if last is not None and pt <= last + PEAK_DISTANCE_S:
                    continue
                events.append((pt, kind))
                last = pt
        # Process in time order so bottoms and tops interleave correctly.
        for pt, kind in sorted(events):
            if kind == "bottom":
                c = self._commit_bottom(pt)
                if self.pending is not None:
                    done.append(self.pending)  # never got a closing top → no depth
                self.pending = c
                bottoms.append(c)
            else:
                self._commit_top(pt, ts)
                if self.pending is not None and self.pending.t < pt:
                    done.append(self.pending)
                    self.pending = None

        if self.pending is not None and now - self.pending.t > 1.5:
            done.append(self.pending)
            self.pending = None
        return bottoms, done

    def _commit_bottom(self, pt: float) -> Compression:
        interval = pt - self.last_bottom if self.last_bottom is not None else None
        inst = None
        if interval is not None and interval <= MAX_INTERVAL_S:
            self.intervals.append(interval)
            inst = 60.0 / interval
        self.last_bottom = pt
        self.count += 1
        return Compression(t=pt, interval_s=interval, inst_rate_cpm=inst)

    def _commit_top(self, pt: float, ts: np.ndarray) -> None:
        self.prev_top, self.last_top = self.last_top, pt
        c = self.pending
        t0 = self.prev_top
        if c is None or t0 is None or not (t0 < c.t < pt):
            return
        if any(t0 <= d <= pt for d in self.discontinuities):
            return
        mask = (ts >= t0) & (ts <= pt)
        raw = np.fromiter(self.raw, float)[mask]
        c.depth_cm = cycle_depth_cm(ts[mask], raw, self.depth_scale)
