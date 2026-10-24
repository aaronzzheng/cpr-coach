"""Watch simulator: connects to /ingest like the iPhone relay and streams the exact same binary
CPR1 packets (0x01 + packet, 20 samples every 200 ms) from a synthetic rescuer.

    python -m tools.sim_watch --scenario shallow
    python -m tools.sim_watch --interactive      # + / - rate, [ / ] depth, p pause, q quit
"""

from __future__ import annotations

import argparse
import asyncio
import contextlib
import json
import math
import sys
import time

import numpy as np
from websockets.asyncio.client import connect

from app.ingest import FRAME_IMU, encode_packet
from tools.synth import SynthWatch

BATCH = 20
PERIOD_S = BATCH / 100.0

SCENARIOS: dict[str, dict] = {
    "good": {"rate": 110, "depth": 5.5},
    "shallow": {"rate": 110, "depth": 4.0},
    "fast": {"rate": 135, "depth": 5.5},
    "slow": {"rate": 85, "depth": 5.5},
    "fatigue": {"rate": 110, "depth": 5.6, "fatigue": 0.25, "duration": 150, "hr_start": 85, "hr_end": 130},
    "chaotic": {"rate": 110, "depth": 5.2, "wobble": True, "pause_at": "20:3", "drop_rate": 0.02},
}


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--url", default="ws://localhost:8000/ingest")
    ap.add_argument("--scenario", choices=sorted(SCENARIOS), default="good")
    ap.add_argument("--rate", type=float, help="compressions per minute")
    ap.add_argument("--depth", type=float, help="cm")
    ap.add_argument("--noise", type=float, default=0.3, help="m/s² per axis")
    ap.add_argument("--duration", type=float, help="seconds (default: run forever)")
    ap.add_argument("--fatigue", type=float, help="fractional depth loss over the duration, e.g. 0.25")
    ap.add_argument("--pause-at", help="START:SECONDS, e.g. 45:3")
    ap.add_argument("--hr-start", type=float)
    ap.add_argument("--hr-end", type=float)
    ap.add_argument("--drop-rate", type=float, help="probability a batch is dropped")
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--interactive", action="store_true")
    args = ap.parse_args()

    sc = SCENARIOS[args.scenario]
    for key, default in (
        ("rate", 110.0),
        ("depth", 5.5),
        ("duration", None),
        ("fatigue", 0.0),
        ("pause_at", None),
        ("hr_start", 85.0),
        ("hr_end", None),
        ("drop_rate", 0.0),
    ):
        if getattr(args, key) is None:
            setattr(args, key, sc.get(key, default))
    args.wobble = sc.get("wobble", False)
    if args.hr_end is None:
        args.hr_end = args.hr_start + 20
    return args


class Live:
    """Mutable rate/depth so interactive keys can change them mid-stream."""

    def __init__(self, args: argparse.Namespace) -> None:
        self.args = args
        self.rate = args.rate
        self.depth = args.depth

    def rate_at(self, t: float) -> float:
        if self.args.wobble:
            return self.rate + 18 * math.sin(2 * math.pi * t / 23)
        return self.rate

    def depth_at(self, t: float) -> float:
        d = self.depth
        if self.args.wobble:
            d += 0.9 * math.sin(2 * math.pi * t / 31)
        if self.args.fatigue and self.args.duration:
            d *= 1 - self.args.fatigue * min(t / self.args.duration, 1.0)
        return d


async def read_keys(live: Live, synth: SynthWatch, stop: asyncio.Event) -> None:
    import termios
    import tty

    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)
    tty.setcbreak(fd)
    loop = asyncio.get_running_loop()
    queue: asyncio.Queue[str] = asyncio.Queue()
    loop.add_reader(fd, lambda: queue.put_nowait(sys.stdin.read(1)))
    try:
        while not stop.is_set():
            k = await queue.get()
            if k == "+" or k == "=":
                live.rate += 5
            elif k == "-":
                live.rate -= 5
            elif k == "]":
                live.depth += 0.5
            elif k == "[":
                live.depth -= 0.5
            elif k == "p":
                synth.paused = not synth.paused
            elif k == "q":
                stop.set()
    finally:
        loop.remove_reader(fd)
        termios.tcsetattr(fd, termios.TCSADRAIN, old)


async def stream(args: argparse.Namespace) -> None:
    live = Live(args)
    pauses = []
    if args.pause_at:
        s, d = args.pause_at.split(":")
        pauses.append((float(s), float(d)))
    synth = SynthWatch(
        rate_cpm=live.rate_at, depth_cm=live.depth_at, noise=args.noise, pauses=pauses, seed=args.seed
    )
    rng = np.random.default_rng(args.seed + 1)
    stop = asyncio.Event()

    async with connect(args.url, max_size=None) as ws:
        await ws.send(json.dumps({"t": "hello", "device": "sim", "app_version": "0.1"}))
        print(f"connected to {args.url} — scenario={args.scenario} rate={live.rate} depth={live.depth}")

        async def drain() -> None:
            async for msg in ws:
                print(f"\n← {msg}")

        tasks = [asyncio.create_task(drain())]
        if args.interactive:
            tasks.append(asyncio.create_task(read_keys(live, synth, stop)))

        seq = drops = 0
        start = time.monotonic()
        try:
            while not stop.is_set():
                t = synth.t
                if args.duration and t >= args.duration:
                    break
                ts, ua, g, rr, _ = synth.next(BATCH)
                if rng.random() >= args.drop_rate:
                    await ws.send(bytes([FRAME_IMU]) + encode_packet(seq, ts, ua, g, rr))
                else:
                    drops += 1
                seq += 1

                if seq % 25 == 0:  # every 5 s
                    frac = min(t / args.duration, 1.0) if args.duration else min(t / 120, 1.0)
                    bpm = args.hr_start + (args.hr_end - args.hr_start) * frac
                    await ws.send(json.dumps({"t": "hr", "bpm": round(bpm), "ts": float(ts[-1]), "phone_rx": time.time()}))
                if seq % 10 == 0:  # every 2 s
                    await ws.send(json.dumps({"t": "status", "watch_reachable": True, "drops": drops}))

                state = "PAUSED" if synth.in_pause() else f"{live.rate_at(t):5.1f}/min {live.depth_at(t):4.2f} cm"
                print(f"\r t={t:6.1f}s  {state}  seq={seq} drops={drops}   ", end="", flush=True)

                # Absolute schedule so batches don't drift late.
                await asyncio.sleep(max(0.0, start + seq * PERIOD_S - time.monotonic()))
        finally:
            for task in tasks:
                task.cancel()
                with contextlib.suppress(asyncio.CancelledError):
                    await task
            print()


def main() -> None:
    args = parse_args()
    try:
        asyncio.run(stream(args))
    except KeyboardInterrupt:
        pass
    except OSError as e:
        sys.exit(f"could not connect to {args.url}: {e} — is the backend running (make dev)?")


if __name__ == "__main__":
    main()
