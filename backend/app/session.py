"""Session state machine, pause/hands-off/CCF tracking, per-compression grading and scoring."""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime

from .config import SESSION_CLOCK_GRACE_S, TARGETS


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
    graded: list[tuple[bool, bool | None]] = field(default_factory=list)

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

    def on_graded(self, rate_ok: bool, depth_ok: bool | None) -> None:
        if self.status == "running":
            self.graded.append((rate_ok, depth_ok))

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
        return sum(r for r, _ in self.graded) / len(self.graded) if self.graded else None

    def depth_pct(self) -> float | None:
        ds = [d for _, d in self.graded if d is not None]
        return sum(ds) / len(ds) if ds else None
