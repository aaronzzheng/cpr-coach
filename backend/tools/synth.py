"""Synthetic watch motion: x(t) = D/2·(1 − cos φ), a_down = D/2·ω²·cos φ, rotated into a random
device orientation. Shared by the simulator and the DSP tests."""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass, field

import numpy as np

from app.config import G0, IMU_FS


def random_rotation(rng: np.random.Generator) -> np.ndarray:
    q, r = np.linalg.qr(rng.normal(size=(3, 3)))
    q *= np.sign(np.diag(r))
    if np.linalg.det(q) < 0:
        q[:, 0] *= -1
    return q


@dataclass
class SynthWatch:
    """Stateful generator so rate/depth can change live. Call `next(n)` for n samples."""

    rate_cpm: float | Callable[[float], float] = 110.0
    depth_cm: float | Callable[[float], float] = 5.5
    noise: float = 0.3  # m/s², per axis
    pauses: list[tuple[float, float]] = field(default_factory=list)  # (start_s, duration_s)
    seed: int = 0
    fs: float = IMU_FS
    boot_ts: float = 1000.0
    paused: bool = False

    def __post_init__(self) -> None:
        self.rng = np.random.default_rng(self.seed)
        self.R = random_rotation(self.rng)  # device ← world
        self.g_dev = self.R @ np.array([0.0, 0.0, -1.0])
        self.t = 0.0
        self.phase = 0.0

    def _val(self, v: float | Callable[[float], float]) -> float:
        return v(self.t) if callable(v) else v

    def in_pause(self) -> bool:
        return self.paused or any(s <= self.t < s + d for s, d in self.pauses)

    def next(self, n: int) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
        """Returns ts, ua (g), g (g), rotation rate, and the true a_up (m/s²)."""
        ts = np.empty(n)
        a_down = np.zeros(n)
        dt = 1.0 / self.fs
        for i in range(n):
            ts[i] = self.boot_ts + self.t
            if not self.in_pause():
                w = 2 * np.pi * self._val(self.rate_cpm) / 60.0
                d_m = self._val(self.depth_cm) / 100.0
                a_down[i] = d_m / 2 * w * w * np.cos(self.phase)
                self.phase += w * dt
            elif np.cos(self.phase) < 0.999:
                # Finish the current stroke back to the top before resting, like a real rescuer.
                w = 2 * np.pi * self._val(self.rate_cpm) / 60.0
                a_down[i] = self._val(self.depth_cm) / 100.0 / 2 * w * w * np.cos(self.phase)
                self.phase += w * dt
            self.t += dt
        ua_world = np.outer(a_down / G0, [0.0, 0.0, -1.0])
        ua = ua_world @ self.R.T + self.rng.normal(scale=self.noise / G0, size=(n, 3))
        g = np.tile(self.g_dev, (n, 1))
        rr = self.rng.normal(scale=0.02, size=(n, 3))
        return ts, ua, g, rr, -a_down
