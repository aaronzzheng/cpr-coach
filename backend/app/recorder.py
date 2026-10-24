"""Session recorder: appends every raw IMU packet, heart-rate message and compression event to
data/sessions/<id>/stream.jsonl with the laptop receive time, so tools/replay.py can replay it."""

from __future__ import annotations

import base64
import json
from pathlib import Path
from typing import IO


class Recorder:
    def __init__(self) -> None:
        self._f: IO[str] | None = None
        self.path: Path | None = None

    @property
    def active(self) -> bool:
        return self._f is not None

    def start(self, session_dir: Path, meta: dict) -> None:
        self.stop()
        session_dir.mkdir(parents=True, exist_ok=True)
        self.path = session_dir / "stream.jsonl"
        self._f = self.path.open("w")
        self._write({"k": "meta", **meta})

    def stop(self) -> None:
        if self._f:
            self._f.close()
        self._f = None

    def _write(self, obj: dict) -> None:
        if self._f:
            self._f.write(json.dumps(obj, separators=(",", ":")) + "\n")

    def imu(self, rx: float, packet: bytes) -> None:
        self._write({"k": "imu", "rx": rx, "b64": base64.b64encode(packet).decode()})

    def text(self, rx: float, msg: dict) -> None:
        self._write({"k": "text", "rx": rx, "msg": msg})

    def compression(self, rx: float, event: dict) -> None:
        self._write({"k": "comp", "rx": rx, "ev": event})
