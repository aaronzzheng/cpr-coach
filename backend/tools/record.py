"""Record a golden session for backup replay (PRD §12 M5).

With the real watch streaming:   python -m tools.record ../recordings/good.jsonl
  (do compressions, press Enter to stop)
With the simulator instead:      python -m tools.record ../recordings/fatigue.jsonl --sim fatigue --duration 150

The backend (make dev / make demo) must be running. Replay with `make replay SESSION=recordings/good.jsonl`.
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import urllib.request
from pathlib import Path

from app.config import DATA_DIR


def post(base: str, path: str, body: dict | None = None) -> dict:
    req = urllib.request.Request(
        base + path,
        data=json.dumps(body or {}).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=10) as r:
        return json.load(r)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("out", type=Path, help="where to write the .jsonl recording")
    ap.add_argument("--base", default="http://localhost:8000")
    ap.add_argument("--name", default="Golden session")
    ap.add_argument("--sim", metavar="SCENARIO", help="drive the session with tools.sim_watch instead of the real watch")
    ap.add_argument("--duration", type=float, default=60, help="seconds (with --sim)")
    args = ap.parse_args()

    sid = post(args.base, "/api/session/start", {"name": args.name})["session_id"]
    print(f"recording session {sid}")
    try:
        if args.sim:
            ws = args.base.replace("http", "ws", 1) + "/ingest"
            subprocess.run(
                [sys.executable, "-m", "tools.sim_watch", "--scenario", args.sim, "--duration", str(args.duration), "--url", ws],
                check=True,
            )
        else:
            input("Streaming from the watch. Do compressions, then press Enter to stop… ")
    finally:
        post(args.base, "/api/session/stop")
        summary = post(args.base, f"/api/session/{sid}/summary", {})

    src = DATA_DIR / "sessions" / sid / "stream.jsonl"
    args.out.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(src, args.out)
    print(f"saved {args.out} ({args.out.stat().st_size // 1024} KB) — score {summary['score']:.0f} {summary['grade']}")


if __name__ == "__main__":
    main()
