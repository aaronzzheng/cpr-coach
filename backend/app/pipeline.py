"""Watch pipeline: per IMU packet → vertical projection → band-pass → compression and depth
detection → fatigue. DSP runs on the watch clock; outputs are mapped to laptop time."""

from __future__ import annotations

from collections import deque
from dataclasses import dataclass

import numpy as np

from .config import (
    CLOCK_JUMP_S,
    CLOCK_OFFSET_WINDOW,
    DEPTH_WINDOW,
    FATIGUE_RESET_PAUSE_S,
    IMU_FS,
    WAVE_FS,
    WAVE_S,
)
from .dsp.compressions import Compression, CompressionDetector
from .dsp.fatigue import FatigueModel, FatigueState
from .dsp.filters import StreamingBandpass
from .dsp.vertical import vertical_accel
from .ingest import ImuPacket, SeqTracker


@dataclass
class PipelineOutput:
    bottoms: list[Compression]  # laptop time
    completed: list[Compression]  # laptop time, depth resolved (or None)


class WatchPipeline:
    def __init__(self, depth_scale: float = 1.0) -> None:
        self.depth_scale = depth_scale
        self.seq = SeqTracker()
        self.reset_dsp()

    def reset_dsp(self) -> None:
        self.filter = StreamingBandpass()
        self.detector = CompressionDetector(depth_scale=self.depth_scale)
        self.fatigue = FatigueModel()
        self.offset: float | None = None
        self.offsets: deque[float] = deque(maxlen=CLOCK_OFFSET_WINDOW)
        self.last_ts: float | None = None
        self.depths: deque[float] = deque(maxlen=DEPTH_WINDOW)
        self.last_depth: float | None = None
        self.wave: deque[tuple[float, float]] = deque(maxlen=int(WAVE_S * IMU_FS))
        self.hr: float | None = None

    def to_laptop(self, t_watch: float) -> float:
        return t_watch + (self.offset or 0.0)

    def process(self, pkt: ImuPacket, recv_time: float) -> PipelineOutput:
        if len(pkt.ts) == 0:
            return PipelineOutput([], [])
        if self.last_ts is not None and pkt.ts[0] < self.last_ts - 1.0:
            # Watch clock went backwards: a new device or a restarted sender.
            self.reset_dsp()
            self.seq.reset()
        elif self.last_ts is not None and pkt.ts[0] - self.last_ts > CLOCK_JUMP_S:
            # Clock jumped forward (e.g. simulator → real watch): the old offset is meaningless.
            self.offsets.clear()
            self.filter.reset()
            self.detector.mark_discontinuity(float(pkt.ts[0]))
        gap = self.seq.check(pkt.seq)
        if gap:
            self.filter.reset()
            self.detector.mark_discontinuity(float(pkt.ts[0]))

        # Laptop = watch + offset. The smallest recent offset has the least transport latency;
        # a rolling window (not an all-time minimum) lets it follow a new sender or clock drift.
        self.offsets.append(recv_time - float(pkt.ts[-1]))
        self.offset = min(self.offsets)
        self.last_ts = float(pkt.ts[-1])

        a_up = vertical_accel(pkt.ua, pkt.g)
        filt = self.filter.process(a_up)
        self.wave.extend(zip(pkt.ts.tolist(), filt.tolist()))

        prev_bottom = self.detector.last_bottom
        bottoms, done = self.detector.push(pkt.ts, a_up, filt)

        for c in bottoms:
            if prev_bottom is not None and c.t - prev_bottom > FATIGUE_RESET_PAUSE_S:
                self.fatigue.reset_cycle(c.t, self.hr)
            prev_bottom = c.t
        for c in done:
            self.fatigue.add_compression(c.t, c.depth_cm)
            if c.depth_cm is not None:
                self.depths.append(c.depth_cm)
                self.last_depth = c.depth_cm
        # Updated per packet (not per broadcast) so the sustained-drop timer runs on the watch clock.
        self.fatigue.update(self.last_ts, self.hr)

        return PipelineOutput(self._to_laptop_all(bottoms), self._to_laptop_all(done))

    def _to_laptop_all(self, cs: list[Compression]) -> list[Compression]:
        return [Compression(self.to_laptop(c.t), c.interval_s, c.inst_rate_cpm, c.depth_cm) for c in cs]

    def fatigue_state(self) -> FatigueState:
        return self.fatigue.state

    def set_depth_scale(self, scale: float) -> None:
        self.depth_scale = scale
        self.detector.depth_scale = scale

    def swap(self) -> None:
        """Operator pressed swap: a new rescuer starts a fresh cycle at their first compression."""
        self.fatigue.reset_cycle(None, self.hr)

    def depth_median(self) -> float | None:
        return float(np.median(self.depths)) if self.depths else None

    def last_compression_laptop(self) -> float | None:
        b = self.detector.last_bottom
        return None if b is None else self.to_laptop(b)

    def wave_samples(self) -> tuple[float, list[float]]:
        """Last WAVE_S of filtered a_up, decimated to WAVE_FS, with laptop-time t0."""
        if not self.wave:
            return 0.0, []
        step = max(1, int(IMU_FS / WAVE_FS))
        pts = list(self.wave)[::step]
        return self.to_laptop(pts[0][0]), [round(v, 3) for _, v in pts]
