from __future__ import annotations

from app.dsp.compressions import Compression
from app.ingest import ImuPacket
from app.pipeline import WatchPipeline
from tools.synth import SynthWatch

BATCH = 20


def run_pipeline(
    synth: SynthWatch, seconds: float, drop: set[int] | None = None, pipeline: WatchPipeline | None = None
) -> tuple[WatchPipeline, list[Compression], list[Compression]]:
    """Feed `seconds` of synthetic motion through the pipeline in 20-sample batches."""
    p = pipeline or WatchPipeline()
    bottoms: list[Compression] = []
    done: list[Compression] = []
    for seq in range(int(seconds * synth.fs / BATCH)):
        ts, ua, g, rr, _ = synth.next(BATCH)
        if drop and seq in drop:
            continue
        out = p.process(ImuPacket(seq, ts, ua, g, rr), recv_time=float(ts[-1]))
        bottoms += out.bottoms
        done += out.completed
    return p, bottoms, done
