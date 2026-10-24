"""Session state machine, pause/hands-off/CCF tracking, per-compression grading and scoring."""

from __future__ import annotations

import statistics
from dataclasses import dataclass, field
from datetime import datetime

from pydantic import BaseModel

from .config import MIN_WATCH_COMPRESSIONS, SESSION_CLOCK_GRACE_S, TARGETS


def grade_letter(score: float) -> str:
    for cutoff, letter in ((90, "A"), (80, "B"), (70, "C"), (60, "D")):
        if score >= cutoff:
            return letter
    return "F"


def compute_score(
    rate_pct: float | None,
    depth_pct: float | None,
    ccf: float | None,
    elbow_pct: float | None = None,
    align_pct: float | None = None,
) -> float:
    """PRD §8.5. Percentages are fractions 0–1; terms that are None are dropped and the
    remaining weights renormalized to 100."""
    terms = [
        (30.0, rate_pct),
        (30.0, depth_pct),
        (20.0, None if ccf is None else min(ccf / TARGETS["ccf_target"], 1.0)),
        (10.0, elbow_pct),
        (10.0, align_pct),
    ]
    used = [(w, v) for w, v in terms if v is not None]
    total = sum(w for w, _ in used)
    if total == 0:
        return 0.0
    return 100.0 * sum(w * v for w, v in used) / total


@dataclass
class Pauses:
    count: int = 0
    longest_s: float = 0.0
    hands_off_s: float = 0.0
    ccf: float | None = None
    in_pause: bool = False
    pause_elapsed_s: float = 0.0


@dataclass
class CompressionRecord:
    t: float  # seconds since the session clock started
    inst_rate_cpm: float | None
    rate_ok: bool | None
    depth_cm: float | None
    depth_ok: bool | None


class CameraMetrics(BaseModel):
    """What the dashboard measured in-browser, posted after stop (PRD §6.3 summary route)."""

    compressions: int = 0
    rate_pct: float | None = None
    depth_pct: float | None = None
    ccf: float | None = None
    elapsed_s: float | None = None
    pauses: int = 0
    longest_pause_s: float = 0.0
    avg_rate_cpm: float | None = None
    avg_depth_cm: float | None = None
    elbow_pct: float | None = None
    align_pct: float | None = None
    depth_series: list[tuple[float, float]] = []


@dataclass
class Session:
    id: str = ""
    name: str = ""
    status: str = "idle"  # idle | running | summary
    started_at: float | None = None
    clock_start: float | None = None
    stopped_at: float | None = None
    last_compression: float | None = None
    pause_count: int = 0
    longest_pause: float = 0.0
    hands_off: float = 0.0
    records: list[CompressionRecord] = field(default_factory=list)
    fatigue_at: float | None = None

    def start(self, now: float, name: str = "") -> None:
        self.__init__()
        self.id = datetime.now().strftime("%Y-%m-%dT%H-%M-%S")
        self.name = name
        self.status = "running"
        self.started_at = now

    def stop(self, now: float) -> None:
        if self.status == "running":
            self._settle_clock(now)
            self.stopped_at = now
            self.status = "summary"

    def _settle_clock(self, now: float) -> None:
        if self.clock_start is None and self.started_at is not None and now - self.started_at >= SESSION_CLOCK_GRACE_S:
            self.clock_start = self.started_at + SESSION_CLOCK_GRACE_S

    def on_compression(self, t: float) -> None:
        if self.status != "running":
            return
        self._settle_clock(t)
        if self.clock_start is None:
            self.clock_start = t
        ref = self.last_compression if self.last_compression is not None else self.clock_start
        gap = t - ref
        if gap > TARGETS["pause_threshold_s"]:
            self.pause_count += 1
            self.longest_pause = max(self.longest_pause, gap)
            self.hands_off += gap
        self.last_compression = t

    def on_graded(
        self, t: float, inst_rate_cpm: float | None, rate_ok: bool, depth_cm: float | None, depth_ok: bool | None
    ) -> None:
        if self.status != "running" or self.clock_start is None:
            return
        self.records.append(
            CompressionRecord(
                t=t - self.clock_start,
                inst_rate_cpm=inst_rate_cpm,
                rate_ok=rate_ok if inst_rate_cpm is not None else None,
                depth_cm=depth_cm,
                depth_ok=depth_ok,
            )
        )

    def mark_fatigue(self, now: float) -> None:
        """Remember the first moment a swap was recommended, for the summary."""
        if self.status == "running" and self.fatigue_at is None and self.clock_start is not None:
            self.fatigue_at = now - self.clock_start

    def elapsed(self, now: float) -> float:
        end = self.stopped_at if self.stopped_at is not None else now
        if self.status == "running":
            self._settle_clock(now)
        return max(0.0, end - self.clock_start) if self.clock_start is not None else 0.0

    def pauses(self, now: float) -> Pauses:
        p = Pauses(count=self.pause_count, longest_s=self.longest_pause, hands_off_s=self.hands_off)
        elapsed = self.elapsed(now)
        if self.status == "running" and self.clock_start is not None:
            ref = self.last_compression if self.last_compression is not None else self.clock_start
            gap = now - ref
            if gap > TARGETS["pause_threshold_s"]:
                p.in_pause = True
                p.pause_elapsed_s = gap
                p.hands_off_s += gap
        if elapsed > 0:
            p.ccf = max(0.0, (elapsed - p.hands_off_s) / elapsed)
        return p

    def rate_pct(self) -> float | None:
        rs = [r.rate_ok for r in self.records if r.rate_ok is not None]
        return sum(rs) / len(rs) if rs else None

    def depth_pct(self) -> float | None:
        ds = [r.depth_ok for r in self.records if r.depth_ok is not None]
        return sum(ds) / len(ds) if ds else None

    def watch_metrics(self, now: float) -> dict:
        """Backend (watch) portion of the summary, returned by /api/session/stop."""
        p = self.pauses(now)
        rates = [r.inst_rate_cpm for r in self.records if r.inst_rate_cpm is not None]
        depths = [r.depth_cm for r in self.records if r.depth_cm is not None]
        return {
            "session_id": self.id,
            "name": self.name,
            "compressions": len(self.records),
            "rate_pct": self.rate_pct(),
            "depth_pct": self.depth_pct(),
            "ccf": p.ccf,
            "elapsed_s": self.elapsed(now),
            "pauses": p.count,
            "longest_pause_s": p.longest_s,
            "avg_rate_cpm": statistics.median(rates) if rates else None,
            "avg_depth_cm": statistics.median(depths) if depths else None,
            "depth_series": [(round(r.t, 2), round(r.depth_cm, 2)) for r in self.records if r.depth_cm is not None],
            "fatigue_at_s": self.fatigue_at,
        }


def build_summary(watch: dict, cam: CameraMetrics, date: str) -> dict:
    """Merge watch and camera metrics into the final summary. The watch is preferred for
    rate/depth/CCF when it saw enough compressions; posture always comes from the camera."""
    use_watch = watch["compressions"] >= MIN_WATCH_COMPRESSIONS
    src = watch if use_watch else cam.model_dump()
    score = compute_score(src["rate_pct"], src["depth_pct"], src["ccf"], cam.elbow_pct, cam.align_pct)
    return {
        "session_id": watch["session_id"],
        "name": watch["name"] or "Anonymous",
        "date": date,
        "source": "watch" if use_watch else "camera",
        "score": round(score, 1),
        "grade": grade_letter(score),
        "compressions": src["compressions"],
        "elapsed_s": src["elapsed_s"],
        "rate_pct": src["rate_pct"],
        "depth_pct": src["depth_pct"],
        "depth_estimated": not use_watch,
        "ccf": src["ccf"],
        "pauses": src["pauses"],
        "longest_pause_s": src["longest_pause_s"],
        "avg_rate_cpm": src["avg_rate_cpm"],
        "avg_depth_cm": src["avg_depth_cm"],
        "elbow_pct": cam.elbow_pct,
        "align_pct": cam.align_pct,
        "depth_series": src["depth_series"],
        "fatigue_at_s": watch["fatigue_at_s"] if use_watch else None,
    }
