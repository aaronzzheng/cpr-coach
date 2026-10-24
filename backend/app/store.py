"""Local JSON persistence under data/: calibration, per-session summaries, and the leaderboard.
Nothing leaves the laptop."""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any

from .config import DEPTH_SCALE_RANGE, LEADERBOARD_SIZE


def _read(path: Path, default: Any) -> Any:
    try:
        return json.loads(path.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return default


def _write(path: Path, obj: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(obj, indent=2))
    os.replace(tmp, path)  # atomic, so a crash never leaves a half-written file


class Store:
    def __init__(self, root: Path) -> None:
        self.root = root

    @property
    def sessions_dir(self) -> Path:
        return self.root / "sessions"

    # Calibration

    def calibration(self) -> dict:
        c = _read(self.root / "calibration.json", {})
        return {"depth_scale": float(c.get("depth_scale", 1.0)), "cm_per_px": c.get("cm_per_px")}

    def save_calibration(self, depth_scale: float | None, cm_per_px: float | None) -> dict:
        c = self.calibration()
        if depth_scale is not None:
            lo, hi = DEPTH_SCALE_RANGE
            if not lo <= depth_scale <= hi:
                raise ValueError(f"depth_scale {depth_scale:.2f} outside {lo}–{hi}")
            c["depth_scale"] = depth_scale
        if cm_per_px is not None:
            if cm_per_px <= 0:
                raise ValueError("cm_per_px must be positive")
            c["cm_per_px"] = cm_per_px
        _write(self.root / "calibration.json", c)
        return c

    # Summaries

    def save_summary(self, summary: dict) -> None:
        _write(self.sessions_dir / summary["session_id"] / "summary.json", summary)

    def summary(self, session_id: str) -> dict | None:
        if "/" in session_id or ".." in session_id:
            return None
        return _read(self.sessions_dir / session_id / "summary.json", None)

    # Leaderboard

    def leaderboard(self) -> list[dict]:
        entries = _read(self.root / "leaderboard.json", [])
        return sorted(entries, key=lambda e: -e["score"])[:LEADERBOARD_SIZE]

    def add_to_leaderboard(self, summary: dict, name: str | None = None) -> list[dict]:
        entries = [e for e in _read(self.root / "leaderboard.json", []) if e["session_id"] != summary["session_id"]]
        entries.append(
            {
                "session_id": summary["session_id"],
                "name": (name or summary["name"] or "Anonymous").strip()[:40],
                "score": summary["score"],
                "grade": summary["grade"],
                "date": summary["date"],
            }
        )
        _write(self.root / "leaderboard.json", entries)
        return self.leaderboard()
