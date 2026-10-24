import pytest

from app.session import Session, compute_score, grade_letter


def test_perfect_score() -> None:
    assert compute_score(1, 1, 0.8, 1, 1) == pytest.approx(100)


def test_formula() -> None:
    # 30*.9 + 30*.5 + 20*min(.6/.8,1) + 10*1 + 10*.5 = 27 + 15 + 15 + 10 + 5 = 72
    assert compute_score(0.9, 0.5, 0.6, 1.0, 0.5) == pytest.approx(72)


def test_reweights_without_depth_or_camera() -> None:
    # Only rate (30) and ccf (20): (30*.8 + 20*1) / 50 * 100 = 88
    assert compute_score(0.8, None, 0.9, None, None) == pytest.approx(88)


def test_no_terms() -> None:
    assert compute_score(None, None, None) == 0


@pytest.mark.parametrize(("score", "letter"), [(95, "A"), (90, "A"), (85, "B"), (70, "C"), (61, "D"), (10, "F")])
def test_grades(score: float, letter: str) -> None:
    assert grade_letter(score) == letter


def test_pause_and_ccf() -> None:
    s = Session()
    s.start(0.0)
    period = 60 / 110
    t = 1.0
    while t < 15:
        s.on_compression(t)
        t += period
    resume = t + 3.0
    t = resume
    while t < 30:
        s.on_compression(t)
        t += period
    last = t - period
    s.stop(last)
    p = s.pauses(last)
    assert p.count == 1
    assert p.longest_s == pytest.approx(3.0 + period, abs=1e-6)
    assert p.ccf == pytest.approx((last - 1.0 - p.hands_off_s) / (last - 1.0))
    assert 0.85 < p.ccf < 0.9


def test_live_pause_counts_toward_hands_off() -> None:
    s = Session()
    s.start(0.0)
    s.on_compression(1.0)
    p = s.pauses(5.0)
    assert p.in_pause and p.pause_elapsed_s == pytest.approx(4.0)
    assert p.ccf == pytest.approx(0.0)


def test_pipeline_pause_detected_once() -> None:
    from tests.helpers import run_pipeline
    from tools.synth import SynthWatch

    s = Session()
    s.start(0.0)
    _, bottoms, _ = run_pipeline(SynthWatch(rate_cpm=110, pauses=[(12.0, 3.0)], seed=6), 30)
    for b in bottoms:
        s.on_compression(b.t - bottoms[0].t + 0.5)
    assert s.pause_count == 1
