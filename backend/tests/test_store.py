from pathlib import Path

import pytest

from app.session import CameraMetrics, build_summary
from app.store import Store


def _summary(sid: str, score: float, name: str = "A") -> dict:
    return {"session_id": sid, "name": name, "score": score, "grade": "B", "date": "2026-10-24T10:00:00"}


def test_leaderboard_sorted_top10_and_persistent(tmp_path: Path) -> None:
    s = Store(tmp_path)
    for i in range(12):
        s.add_to_leaderboard(_summary(f"s{i}", float(i)))
    board = Store(tmp_path).leaderboard()  # fresh instance = backend restart
    assert [e["score"] for e in board] == [11, 10, 9, 8, 7, 6, 5, 4, 3, 2]


def test_leaderboard_readd_replaces(tmp_path: Path) -> None:
    s = Store(tmp_path)
    s.add_to_leaderboard(_summary("x", 50))
    board = s.add_to_leaderboard(_summary("x", 50), name="Judge Alice")
    assert len(board) == 1 and board[0]["name"] == "Judge Alice"


def test_calibration_validation(tmp_path: Path) -> None:
    s = Store(tmp_path)
    assert s.calibration() == {"depth_scale": 1.0, "cm_per_px": None}
    s.save_calibration(1.2, None)
    s.save_calibration(None, 0.21)
    assert Store(tmp_path).calibration() == {"depth_scale": 1.2, "cm_per_px": 0.21}
    with pytest.raises(ValueError):
        s.save_calibration(3.0, None)


def test_summary_path_traversal_blocked(tmp_path: Path) -> None:
    assert Store(tmp_path).summary("../../etc") is None


WATCH = {
    "session_id": "s1",
    "name": "",
    "compressions": 60,
    "rate_pct": 1.0,
    "depth_pct": 0.5,
    "ccf": 0.8,
    "elapsed_s": 33.0,
    "pauses": 1,
    "longest_pause_s": 3.0,
    "avg_rate_cpm": 110.0,
    "avg_depth_cm": 5.0,
    "depth_series": [(0.5, 5.0)],
    "fatigue_at_s": 25.0,
}


def test_summary_prefers_watch_and_adds_posture() -> None:
    cam = CameraMetrics(compressions=55, rate_pct=0.2, depth_pct=0.1, ccf=0.5, elbow_pct=1.0, align_pct=0.5)
    s = build_summary(WATCH, cam, "d")
    assert s["source"] == "watch"
    # 30*1 + 30*.5 + 20*1 + 10*1 + 10*.5 = 80
    assert s["score"] == 80 and s["grade"] == "B"
    assert s["name"] == "Anonymous" and s["fatigue_at_s"] == 25.0


def test_summary_falls_back_to_camera() -> None:
    cam = CameraMetrics(compressions=40, rate_pct=0.5, depth_pct=None, ccf=1.0, elapsed_s=20)
    s = build_summary({**WATCH, "compressions": 3}, cam, "d")
    assert s["source"] == "camera" and s["depth_estimated"]
    # rate 30*.5 + ccf 20*1 = 35 over weight 50 → 70
    assert s["score"] == 70 and s["fatigue_at_s"] is None
