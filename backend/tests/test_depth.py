import numpy as np
import pytest

from app.dsp.depth import cycle_depth_cm
from tests.helpers import run_pipeline
from tools.synth import SynthWatch


def test_single_cycle_exact() -> None:
    f, d = 110 / 60, 0.055
    t = np.arange(0, 1 / f, 0.01)
    t = np.append(t, 1 / f)
    a_up = -(d / 2) * (2 * np.pi * f) ** 2 * np.cos(2 * np.pi * f * t)
    assert cycle_depth_cm(t, a_up) == pytest.approx(5.5, abs=0.1)


def test_rejects_implausible_cycles() -> None:
    t = np.linspace(0, 0.2, 21)
    assert cycle_depth_cm(t, np.zeros_like(t)) is None
    t = np.linspace(0, 2.0, 201)
    assert cycle_depth_cm(t, np.zeros_like(t)) is None


def test_scale_applies() -> None:
    f, d = 110 / 60, 0.05
    t = np.linspace(0, 1 / f, 60)
    a_up = -(d / 2) * (2 * np.pi * f) ** 2 * np.cos(2 * np.pi * f * t)
    assert cycle_depth_cm(t, a_up, scale=1.2) == pytest.approx(6.0, abs=0.15)


@pytest.mark.parametrize("depth", [4.0, 5.5, 6.5])
def test_pipeline_depth_with_noise(depth: float) -> None:
    _, _, done = run_pipeline(SynthWatch(rate_cpm=110, depth_cm=depth, noise=0.3, seed=2), 30)
    depths = [c.depth_cm for c in done if c.depth_cm is not None]
    assert len(depths) >= 45
    assert abs(float(np.median(depths)) - depth) <= 0.5
