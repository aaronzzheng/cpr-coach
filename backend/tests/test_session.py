"""Session pause tracking and patient depth targets."""

from app.session import Session


def test_planned_pause_is_not_a_pause():
    s = Session()
    s.start(0.0)
    for i in range(10):
        s.on_compression(1.0 + i * 0.5)
    s.planned_pause = True  # rescue breaths
    s.on_compression(1.0 + 9 * 0.5 + 6.0)
    assert s.pause_count == 0
    s.on_compression(1.0 + 9 * 0.5 + 6.0 + 4.0)  # an unplanned 4 s gap still counts
    assert s.pause_count == 1


def test_infant_depth_range():
    s = Session()
    s.start(0.0, patient="infant")
    assert s.depth_range == (3.5, 4.5)
    s.start(0.0, patient="bogus")
    assert s.patient == "adult"
