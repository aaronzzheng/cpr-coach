"""Streaming Butterworth band-pass (sosfilt with persistent zi), reset on discontinuities."""

from __future__ import annotations

import numpy as np
from scipy.signal import butter, sosfilt, sosfilt_zi

from ..config import BANDPASS_HZ, BANDPASS_ORDER, IMU_FS


class StreamingBandpass:
    def __init__(
        self, fs: float = IMU_FS, band: tuple[float, float] = BANDPASS_HZ, order: int = BANDPASS_ORDER
    ) -> None:
        self.sos = butter(order, band, btype="band", fs=fs, output="sos")
        self._zi_unit = sosfilt_zi(self.sos)
        self.zi: np.ndarray | None = None

    def reset(self) -> None:
        self.zi = None

    def process(self, x: np.ndarray) -> np.ndarray:
        if len(x) == 0:
            return x
        if self.zi is None:
            # Start in steady state for the first sample to avoid a big start-up transient.
            self.zi = self._zi_unit * x[0]
        y, self.zi = sosfilt(self.sos, x, zi=self.zi)
        return y
