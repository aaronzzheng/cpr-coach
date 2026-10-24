"""Accuracy validation: record labelled sessions, then measure rate and depth error against the labels.

Rate trials: the laptop plays a click track at a known BPM; compress on the beat.
    python -m tools.validate run --rate 100
Depth trials: compress to a hard stop of known depth (e.g. a foam block on a ruler); 110 BPM click.
    python -m tools.validate run --depth 5
Simulator trials (checks the tool itself, no watch needed):
    python -m tools.validate run --rate 120 --sim
Report over every trial in recordings/val (prints a table, writes recordings/val/report.html):
    python -m tools.validate report

The backend must be running for `run`. `report` runs the same DSP pipeline offline over the recordings,
with the saved depth calibration, and drops the first and last seconds of each trial.
"""

from __future__ import annotations

import argparse
import base64
import html
import json
import math
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import time
import wave
from dataclasses import dataclass
from pathlib import Path

import numpy as np

from app.config import DATA_DIR, REPO_ROOT
from app.ingest import decode_packet
from app.pipeline import WatchPipeline
from tools.record import post

VAL_DIR = REPO_ROOT / "recordings" / "val"
LEAD_IN_S = 4.0  # clicks before compressions start; trimmed from the analysis
TRIM_END_S = 1.5
RATE_TOL = 5.0  # cpm
DEPTH_TOL = 0.5  # cm


# MARK: run


def click_track(bpm: float, seconds: float, path: Path) -> None:
    """Mono 16-bit WAV of short clicks; one file played by one process keeps the beat exact."""
    sr = 44100
    n = int(sr * seconds)
    out = np.zeros(n)
    click = np.sin(2 * np.pi * 1500 * np.arange(int(0.03 * sr)) / sr) * np.exp(
        -np.arange(int(0.03 * sr)) / (0.006 * sr)
    )
    period = 60.0 / bpm
    k = 0
    while (start := int(k * period * sr)) + len(click) < n:
        out[start : start + len(click)] += click * (1.0 if k % 4 else 0.6)
        k += 1
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(b"".join(struct.pack("<h", int(v * 30000)) for v in out))


def run(args: argparse.Namespace) -> None:
    if (args.rate is None) == (args.depth is None):
        sys.exit("give exactly one of --rate BPM or --depth CM")
    label = f"rate-{args.rate:g}" if args.rate is not None else f"depth-{args.depth:g}"
    bpm = args.rate if args.rate is not None else 110.0
    out = (
        VAL_DIR / f"{label}{'-sim' if args.sim else ''}-{time.strftime('%H%M%S')}.jsonl"
    )

    sid = post(args.base, "/api/session/start", {"name": f"Validation {label}"})[
        "session_id"
    ]
    print(
        f"{label}: {args.seconds:.0f} s at {bpm:g} BPM. Start on the beat after the first {LEAD_IN_S:.0f} seconds of clicks."
    )
    try:
        if args.sim:
            ws = args.base.replace("http", "ws", 1) + "/ingest"
            depth = args.depth if args.depth is not None else 5.5
            subprocess.run(
                [
                    sys.executable,
                    "-m",
                    "tools.sim_watch",
                    "--rate",
                    str(bpm),
                    "--depth",
                    str(depth),
                    "--duration",
                    str(args.seconds + LEAD_IN_S),
                    "--url",
                    ws,
                    "--seed",
                    str(int(time.time()) % 1000),
                ],
                check=True,
            )
        else:
            with tempfile.TemporaryDirectory() as tmp:
                wav = Path(tmp) / "click.wav"
                click_track(bpm, args.seconds + LEAD_IN_S, wav)
                subprocess.run(["afplay", str(wav)], check=True)
    finally:
        post(args.base, "/api/session/stop")

    VAL_DIR.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(DATA_DIR / "sessions" / sid / "stream.jsonl", out)
    print(f"saved {out.relative_to(REPO_ROOT)}")


# MARK: report


@dataclass
class Trial:
    name: str
    kind: str  # "rate" | "depth"
    label: float
    rates: list[float]
    depths: list[float]

    @property
    def measured(self) -> list[float]:
        return self.rates if self.kind == "rate" else self.depths

    @property
    def tol(self) -> float:
        return RATE_TOL if self.kind == "rate" else DEPTH_TOL


def analyse(path: Path, depth_scale: float) -> Trial | None:
    m = re.match(r"(rate|depth)-([\d.]+)", path.name)
    if not m:
        return None
    pipe = WatchPipeline(depth_scale=depth_scale)
    done = []
    with path.open() as f:
        for line in f:
            rec = json.loads(line)
            if rec["k"] != "imu":
                continue
            out = pipe.process(decode_packet(base64.b64decode(rec["b64"])), rec["rx"])
            done += out.completed
    if not done:
        return Trial(path.stem, m[1], float(m[2]), [], [])
    t0, t1 = done[0].t, done[-1].t
    keep = [c for c in done if t0 + LEAD_IN_S - 2 <= c.t <= t1 - TRIM_END_S] or done
    return Trial(
        path.stem,
        m[1],
        float(m[2]),
        rates=[c.inst_rate_cpm for c in keep if c.inst_rate_cpm is not None],
        depths=[c.depth_cm for c in keep if c.depth_cm is not None],
    )


def stats(t: Trial) -> dict[str, float]:
    x = np.array(t.measured)
    if len(x) == 0:
        return {
            "n": 0,
            "median": math.nan,
            "bias": math.nan,
            "mae": math.nan,
            "within": math.nan,
        }
    err = x - t.label
    return {
        "n": len(x),
        "median": float(np.median(x)),
        "bias": float(np.median(err)),
        "mae": float(np.mean(np.abs(err))),
        "within": float(np.mean(np.abs(err) <= t.tol)),
    }


def chart(trials: list[Trial], kind: str, unit: str) -> str:
    """Inline SVG: every compression as a dot at its labelled value, the identity line for reference."""
    ts = [t for t in trials if t.kind == kind and t.measured]
    if not ts:
        return ""
    W, H, P = 560, 320, 48
    vals = [v for t in ts for v in t.measured] + [t.label for t in ts]
    lo, hi = min(vals), max(vals)
    pad = (hi - lo) * 0.12 or 1
    lo, hi = lo - pad, hi + pad
    sx = lambda v: P + (v - lo) / (hi - lo) * (W - 2 * P)
    sy = lambda v: H - P + -(v - lo) / (hi - lo) * (H - 2 * P)
    parts = [
        f'<svg viewBox="0 0 {W} {H}" role="img" aria-label="{kind} measured vs actual">'
    ]
    for g in np.linspace(lo, hi, 5):
        parts.append(
            f'<line class="grid" x1="{P}" x2="{W - P}" y1="{sy(g):.1f}" y2="{sy(g):.1f}"/>'
        )
        parts.append(
            f'<text class="tick" x="{P - 8}" y="{sy(g) + 4:.1f}" text-anchor="end">{g:.3g}</text>'
        )
        parts.append(
            f'<text class="tick" x="{sx(g):.1f}" y="{H - P + 18}" text-anchor="middle">{g:.3g}</text>'
        )
    parts.append(
        f'<line class="ident" x1="{sx(lo):.1f}" y1="{sy(lo):.1f}" x2="{sx(hi):.1f}" y2="{sy(hi):.1f}"/>'
    )
    rng = np.random.default_rng(0)
    for t in ts:
        for v in t.measured:
            jx = rng.uniform(-6, 6)
            tip = html.escape(
                f"{t.name}: actual {t.label:g} {unit}, measured {v:.1f} {unit}"
            )
            parts.append(
                f'<circle class="dot" cx="{sx(t.label) + jx:.1f}" cy="{sy(v):.1f}" r="4"><title>{tip}</title></circle>'
            )
        med = float(np.median(t.measured))
        parts.append(
            f'<rect class="med" x="{sx(t.label) - 14:.1f}" y="{sy(med) - 1.5:.1f}" width="28" height="3" rx="1.5"/>'
        )
    parts.append(
        f'<text class="axis" x="{W / 2}" y="{H - 8}" text-anchor="middle">Actual {kind} ({unit})</text>'
    )
    parts.append(
        f'<text class="axis" transform="translate(14 {H / 2}) rotate(-90)" text-anchor="middle">Measured ({unit})</text>'
    )
    parts.append("</svg>")
    return "".join(parts)


def report(args: argparse.Namespace) -> None:
    scale = (
        json.loads((DATA_DIR / "calibration.json").read_text())["depth_scale"]
        if (DATA_DIR / "calibration.json").exists()
        else 1.0
    )
    trials = [t for p in sorted(args.dir.glob("*.jsonl")) if (t := analyse(p, scale))]
    if not trials:
        sys.exit(f"no rate-*/depth-* recordings in {args.dir}")

    rows = []
    print(
        f"{'trial':32} {'n':>4} {'actual':>7} {'median':>7} {'bias':>6} {'MAE':>6} {'within tol':>10}"
    )
    for t in trials:
        s = stats(t)
        print(
            f"{t.name:32} {s['n']:>4} {t.label:>7g} {s['median']:>7.1f} {s['bias']:>+6.1f} {s['mae']:>6.2f} {s['within']:>9.0%}"
        )
        rows.append((t, s))
    summary = []
    for kind, unit, tol in (("rate", "/min", RATE_TOL), ("depth", "cm", DEPTH_TOL)):
        errs = np.concatenate(
            [
                np.array(t.measured) - t.label
                for t in trials
                if t.kind == kind and t.measured
            ]
            or [np.array([])]
        )
        if len(errs):
            line = (
                f"{kind}: {len(errs)} compressions, MAE {np.mean(np.abs(errs)):.2f} {unit}, "
                f"{np.mean(np.abs(errs) <= tol):.0%} within ±{tol:g} {unit}"
            )
            print(line)
            summary.append((kind, unit, tol, errs))

    tiles = "".join(
        f'<div class="tile"><div class="k">{kind.title()} accuracy</div>'
        f'<div class="v">{np.mean(np.abs(e) <= tol):.0%}</div>'
        f'<div class="s">of {len(e)} compressions within ±{tol:g} {unit} · MAE {np.mean(np.abs(e)):.2f} {unit}</div></div>'
        for kind, unit, tol, e in summary
    )
    table = "".join(
        f"<tr><td>{html.escape(t.name)}</td><td>{s['n']}</td><td>{t.label:g}</td><td>{s['median']:.1f}</td>"
        f"<td>{s['bias']:+.1f}</td><td>{s['mae']:.2f}</td><td>{s['within']:.0%}</td></tr>"
        for t, s in rows
    )
    page = f"""<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Accuracy Validation</title><style>
:root{{--bg:#fff;--fg:#1d1d1f;--muted:#6e6e73;--line:#e5e5ea;--dot:#0a84ff;--ink:#1d1d1f}}
@media (prefers-color-scheme:dark){{:root{{--bg:#000;--fg:#f5f5f7;--muted:#a1a1a6;--line:#2c2c2e;--dot:#64d2ff;--ink:#f5f5f7}}}}
body{{margin:0;background:var(--bg);color:var(--fg);font:15px/1.45 -apple-system,BlinkMacSystemFont,system-ui,sans-serif}}
main{{max-width:1180px;margin:0 auto;padding:40px 16px}} h1{{font-size:32px;letter-spacing:-.02em;margin:0 0 6px}}
p.sub{{color:var(--muted);margin:0 0 28px}} .tiles{{display:flex;gap:16px;flex-wrap:wrap;margin-bottom:28px}}
.tile{{flex:1 1 260px;border:1px solid var(--line);border-radius:18px;padding:18px 20px}} .k{{color:var(--muted);font-weight:600;font-size:13px}}
.v{{font-size:48px;font-weight:700;letter-spacing:-.03em;font-variant-numeric:tabular-nums}} .s{{color:var(--muted);font-size:13px}}
.charts{{display:flex;gap:16px;flex-wrap:wrap}} figure{{flex:1 1 420px;margin:0;border:1px solid var(--line);border-radius:18px;padding:12px}}
figcaption{{font-weight:600;padding:4px 8px}} svg{{width:100%;height:auto}} .grid{{stroke:var(--line);stroke-width:1}}
.ident{{stroke:var(--muted);stroke-dasharray:4 4;stroke-width:1}} .dot{{fill:var(--dot);fill-opacity:.55;stroke:var(--bg);stroke-width:1}}
.dot:hover{{fill-opacity:1}} .med{{fill:var(--ink)}} .tick,.axis{{fill:var(--muted);font-size:11px}}
table{{width:100%;border-collapse:collapse;margin-top:28px;font-variant-numeric:tabular-nums}} th,td{{text-align:right;padding:8px 10px;border-bottom:1px solid var(--line)}}
th:first-child,td:first-child{{text-align:left}} th{{color:var(--muted);font-weight:600;font-size:13px}}
.wrap{{overflow-x:auto}}</style></head><body><main>
<h1>Accuracy validation</h1>
<p class="sub">Each dot is one compression measured by the watch, against the known rate (click track) or depth (hard stop). The dashed line is perfect agreement; the bar is each trial's median.</p>
<div class="tiles">{tiles}</div>
<div class="charts"><figure><figcaption>Rate</figcaption>{chart(trials, "rate", "/min")}</figure>
<figure><figcaption>Depth</figcaption>{chart(trials, "depth", "cm")}</figure></div>
<div class="wrap"><table><thead><tr><th>Trial</th><th>n</th><th>Actual</th><th>Median</th><th>Bias</th><th>MAE</th><th>Within tol.</th></tr></thead>
<tbody>{table}</tbody></table></div></main></body></html>"""
    out = args.dir / "report.html"
    out.write_text(page)
    print(
        f"wrote {out.relative_to(REPO_ROOT) if out.is_relative_to(REPO_ROOT) else out}"
    )


def main() -> None:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("run", help="record one labelled trial")
    r.add_argument("--rate", type=float, help="click-track BPM to follow")
    r.add_argument("--depth", type=float, help="known compression depth (cm)")
    r.add_argument("--seconds", type=float, default=30)
    r.add_argument(
        "--sim", action="store_true", help="drive the trial with the watch simulator"
    )
    r.add_argument("--base", default="http://localhost:8000")
    rep = sub.add_parser("report", help="score every trial")
    rep.add_argument("dir", type=Path, nargs="?", default=VAL_DIR)
    args = ap.parse_args()
    run(args) if args.cmd == "run" else report(args)


if __name__ == "__main__":
    main()
