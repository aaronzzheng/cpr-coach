from app.dsp.fatigue import FatigueModel
from tests.helpers import run_pipeline
from tools.synth import SynthWatch


def _feed(model: FatigueModel, depth_at, until: float, interval: float = 60 / 110) -> float | None:
    t = 0.0
    fired = None
    while t <= until:
        model.add_compression(t, depth_at(t))
        if model.update(t).swap_recommended and fired is None:
            fired = t
        t += interval
    return fired


def test_linear_decay_triggers_swap_before_two_minutes() -> None:
    fired = _feed(FatigueModel(), lambda t: 5.5 - 1.3 * t / 120, until=125)
    assert fired is not None and fired < 120


def test_steady_depth_swaps_only_at_two_minutes() -> None:
    fired = _feed(FatigueModel(), lambda t: 5.5, until=125)
    assert fired is not None and 119 <= fired <= 121


def test_hr_rise_contributes_to_score() -> None:
    m = FatigueModel()
    m.add_compression(0.0, 5.5)
    m.update(0.0, hr=90)
    assert m.update(30.0, hr=120).score == 0.3


def test_end_to_end_fatigue_via_pipeline() -> None:
    # Through the noisy pipeline, the 15 % drop is detected by ~112 s; the 10 s hold then
    # lands right around the 120 s hard limit, so check detection rather than the swap itself.
    synth = SynthWatch(rate_cpm=110, depth_cm=lambda t: 5.5 - 1.3 * t / 120, seed=5)
    p, _, _ = run_pipeline(synth, 115)
    s = p.fatigue_state()
    assert s.depth_drop >= 0.15
    assert p.fatigue.drop_since is not None
    p, _, _ = run_pipeline(synth, 7, pipeline=p)
    assert p.fatigue_state().swap_recommended
