import numpy as np

from app.config import G0
from app.dsp.vertical import vertical_accel
from tools.synth import random_rotation


def test_projection_is_orientation_independent() -> None:
    rng = np.random.default_rng(3)
    a_up_true = rng.normal(size=50) * 5.0
    for _ in range(20):
        R = random_rotation(rng)
        g = np.tile(R @ [0, 0, -1.0], (50, 1))
        ua = np.outer(-a_up_true / G0, [0, 0, -1.0]) @ R.T
        np.testing.assert_allclose(vertical_accel(ua, g), a_up_true, atol=1e-9)


def test_horizontal_motion_is_ignored() -> None:
    g = np.tile([0, 0, -1.0], (10, 1))
    ua = np.tile([0.5, -0.3, 0.0], (10, 1))
    np.testing.assert_allclose(vertical_accel(ua, g), 0.0, atol=1e-12)
