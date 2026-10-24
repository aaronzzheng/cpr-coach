"""Replay a recorded session into /ingest at real speed, exactly as the phone sent it.

    python -m tools.replay data/sessions/2026-10-24T15-02-11
    python -m tools.replay recordings/fatigue.jsonl --speed 2 --loop
"""

from __future__ import annotations

import argparse
import asyncio
import base64
import json
import sys
import time
from pathlib import Path

from websockets.asyncio.client import connect

from app.ingest import FRAME_IMU

REPLAYED_TEXT = {"hr", "status"}


def load(path: Path) -> list[tuple[float, bytes | str]]:
    """Returns (seconds since first frame, frame) for every IMU packet and HR/status message."""
    if path.is_dir():
        path = path / "stream.jsonl"
    frames: list[tuple[float, bytes | str]] = []
    with path.open() as f:
        for line in f:
            rec = json.loads(line)
            if rec["k"] == "imu":
                frames.append((rec["rx"], bytes([FRAME_IMU]) + base64.b64decode(rec["b64"])))
            elif rec["k"] == "text" and rec["msg"].get("t") in REPLAYED_TEXT:
                frames.append((rec["rx"], json.dumps(rec["msg"])))
    if not frames:
        raise ValueError(f"{path} has no IMU data")
    t0 = frames[0][0]
    return [(rx - t0, frame) for rx, frame in frames]


async def replay(frames: list[tuple[float, bytes | str]], url: str, speed: float, loop: bool) -> None:
    async with connect(url, max_size=None) as ws:
        await ws.send(json.dumps({"t": "hello", "device": "replay", "app_version": "0.1"}))
        duration = frames[-1][0]
        print(f"replaying {len(frames)} frames ({duration:.0f} s) at {speed}x → {url}")
        while True:
            start = time.monotonic()
            for i, (t, frame) in enumerate(frames):
                await asyncio.sleep(max(0.0, start + t / speed - time.monotonic()))
                await ws.send(frame)
                if i % 25 == 0:
                    print(f"\r t={t:6.1f}/{duration:.0f} s", end="", flush=True)
            print()
            if not loop:
                break


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("path", type=Path, help="session directory or stream.jsonl")
    ap.add_argument("--url", default="ws://localhost:8000/ingest")
    ap.add_argument("--speed", type=float, default=1.0)
    ap.add_argument("--loop", action="store_true")
    args = ap.parse_args()
    try:
        frames = load(args.path)
        asyncio.run(replay(frames, args.url, args.speed, args.loop))
    except KeyboardInterrupt:
        pass
    except (OSError, ValueError) as e:
        sys.exit(f"replay failed: {e}")


if __name__ == "__main__":
    main()
