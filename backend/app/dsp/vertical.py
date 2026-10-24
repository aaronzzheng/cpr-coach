"""Vertical projection: userAcceleration onto the gravity direction → a_up in m/s².

Orientation-independent, so the watch can sit on either wrist at any angle.
"""

from __future__ import annotations

import numpy as np

from ..config import G0


def vertical_accel(ua: np.ndarray, g: np.ndarray) -> np.ndarray:
    """`ua` and `g` are (n, 3) arrays in g units, device frame. Returns a_up (n,) in m/s²."""
    norm = np.linalg.norm(g, axis=1, keepdims=True)
    g_hat = g / np.where(norm == 0, 1.0, norm)
    a_down = np.einsum("ij,ij->i", ua, g_hat) * G0
    return -a_down
