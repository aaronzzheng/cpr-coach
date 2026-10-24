"""FastAPI entry point: HTTP routes, the phone/simulator /ingest socket, the dashboard /ws
socket, and static serving of the built dashboard."""

from __future__ import annotations

import json
import logging
import time
from collections import deque
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

from . import models as m
from .broadcaster import Broadcaster
from .config import SOURCE_STALE_S, TARGETS, WAVE_FS, WEB_DIST
from .dsp.compressions import Compression
from .ingest import FRAME_IMU, decode_packet
from .pipeline import WatchPipeline
from .session import Session

log = logging.getLogger("cpr")

STARTED_AT = time.time()
pipeline = WatchPipeline()
session = Session()
broadcaster = Broadcaster()


class Ingest:
    """The single phone/simulator connection and its liveness stats."""

    def __init__(self) -> None:
        self.ws: WebSocket | None = None
        self.device = "none"
        self.last_packet: float | None = None
        self.packet_times: deque[float] = deque(maxlen=50)
        self.hr_at: float | None = None
        self.watch_reachable: bool | None = None

    def streaming(self, now: float) -> bool:
        return self.last_packet is not None and now - self.last_packet < SOURCE_STALE_S

    def packet_rate(self, now: float) -> float:
        return sum(1 for t in self.packet_times if now - t <= 2.0) / 2.0

    async def send_cmd(self, cmd: dict) -> None:
        if self.ws is not None:
            try:
                await self.ws.send_text(json.dumps(cmd))
            except Exception:  # noqa: BLE001
                log.warning("failed to forward %s to %s", cmd, self.device)


ingest = Ingest()


def build_state() -> m.StateMsg:
    now = time.time()
    fat = pipeline.fatigue_state()
    p = session.pauses(now)
    t0, wave = pipeline.wave_samples()
    source = "none"
    if ingest.streaming(now):
        source = {"iphone": "watch", "sim": "sim", "replay": "replay"}.get(ingest.device, "watch")
    return m.StateMsg(
        ts=now,
        session=m.SessionInfo(
            id=session.id,
            status=session.status,  # type: ignore[arg-type]
            elapsed_s=round(session.elapsed(now), 2),
            cycle_elapsed_s=round(fat.cycle_elapsed_s, 2),
            name=session.name,
        ),
        sources=m.Sources(
            phone_connected=ingest.ws is not None and ingest.device == "iphone",
            watch_streaming=ingest.streaming(now),
            packet_rate_hz=ingest.packet_rate(now),
            gaps=pipeline.seq.gaps,
            last_packet_age_ms=None if ingest.last_packet is None else int((now - ingest.last_packet) * 1000),
            source=source,  # type: ignore[arg-type]
        ),
        hr=m.Hr(
            bpm=None if pipeline.hr is None else round(pipeline.hr),
            age_s=None if ingest.hr_at is None else round(now - ingest.hr_at, 1),
        ),
        compressions=m.Compressions(
            count=pipeline.detector.count,
            rate_cpm=pipeline.detector.rate_cpm,
            last_depth_cm=pipeline.last_depth,
            depth_avg5_cm=pipeline.depth_median(),
            last_t=pipeline.last_compression_laptop(),
        ),
        pauses=m.PausesMsg(**vars(p)),
        fatigue=m.Fatigue(
            score=round(fat.score, 3),
            baseline_depth_cm=fat.baseline_depth_cm,
            recent_depth_cm=fat.recent_depth_cm,
            swap_recommended=fat.swap_recommended,
        ),
        wave=m.Wave(t0=t0, fs=WAVE_FS, a_up=wave),
    )


def compression_msg(c: Compression) -> m.CompressionMsg:
    rate_ok = c.inst_rate_cpm is not None and TARGETS["rate_min_cpm"] <= c.inst_rate_cpm <= TARGETS["rate_max_cpm"]
    depth_ok = None if c.depth_cm is None else TARGETS["depth_min_cm"] <= c.depth_cm <= TARGETS["depth_max_cm"]
    return m.CompressionMsg(
        t=c.t,
        interval_s=c.interval_s,
        inst_rate_cpm=c.inst_rate_cpm,
        depth_cm=c.depth_cm,
        rate_ok=rate_ok,
        depth_ok=depth_ok,
    )


@asynccontextmanager
async def lifespan(_: FastAPI) -> AsyncIterator[None]:
    broadcaster.start(build_state)
    yield
    await broadcaster.stop()


app = FastAPI(title="CPR Coach", lifespan=lifespan)


@app.get("/api/health")
def health() -> dict:
    now = time.time()
    return {
        "ok": True,
        "uptime_s": round(now - STARTED_AT, 1),
        "sources": {
            "phone_connected": ingest.ws is not None and ingest.device == "iphone",
            "watch_streaming": ingest.streaming(now),
            "source": ingest.device if ingest.ws is not None else "none",
        },
    }


@app.get("/api/targets")
def targets() -> dict:
    return TARGETS


class StartBody(BaseModel):
    name: str = ""


async def start_session(name: str) -> dict:
    session.start(time.time(), name)
    pipeline.swap()
    await ingest.send_cmd({"cmd": "start"})
    return {"session_id": session.id}


async def stop_session() -> dict:
    now = time.time()
    session.stop(now)
    await ingest.send_cmd({"cmd": "stop"})
    p = session.pauses(now)
    return {
        "session_id": session.id,
        "elapsed_s": session.elapsed(now),
        "compressions": pipeline.detector.count,
        "rate_pct": session.rate_pct(),
        "depth_pct": session.depth_pct(),
        "ccf": p.ccf,
        "pauses": p.count,
        "longest_pause_s": p.longest_s,
    }


@app.post("/api/session/start")
async def api_start(body: StartBody) -> dict:
    return await start_session(body.name)


@app.post("/api/session/stop")
async def api_stop() -> dict:
    return await stop_session()


@app.websocket("/ingest")
async def ingest_ws(ws: WebSocket) -> None:
    await ws.accept()
    if ingest.ws is not None:
        log.warning("new ingest connection replaces %s", ingest.device)
    ingest.ws = ws
    ingest.device = "unknown"
    try:
        while True:
            msg = await ws.receive()
            if msg["type"] == "websocket.disconnect":
                break
            now = time.time()
            data = msg.get("bytes")
            if data:
                if data[0] != FRAME_IMU:
                    continue
                try:
                    pkt = decode_packet(data[1:])
                except ValueError as e:
                    log.warning("bad IMU packet: %s", e)
                    continue
                ingest.last_packet = now
                ingest.packet_times.append(now)
                out = pipeline.process(pkt, now)
                for c in out.bottoms:
                    session.on_compression(c.t)
                for c in out.completed:
                    cm = compression_msg(c)
                    if c.inst_rate_cpm is not None:
                        session.on_graded(cm.rate_ok, cm.depth_ok)
                    await broadcaster.send(cm)
            elif msg.get("text"):
                j = json.loads(msg["text"])
                t = j.get("t")
                if t == "hello":
                    ingest.device = j.get("device", "unknown")
                    log.info("ingest hello from %s", ingest.device)
                elif t == "hr":
                    pipeline.hr = float(j["bpm"])
                    ingest.hr_at = now
                elif t == "status":
                    ingest.watch_reachable = j.get("watch_reachable")
    except WebSocketDisconnect:
        pass
    finally:
        if ingest.ws is ws:
            ingest.ws = None


@app.websocket("/ws")
async def dashboard_ws(ws: WebSocket) -> None:
    await ws.accept()
    broadcaster.clients.add(ws)
    try:
        while True:
            j = json.loads(await ws.receive_text())
            cmd = j.get("cmd")
            if cmd == "start":
                await start_session(j.get("name", ""))
            elif cmd == "stop":
                await stop_session()
            elif cmd == "swap":
                pipeline.swap()
            elif cmd == "metronome":
                await ingest.send_cmd({"cmd": "metronome", "on": bool(j.get("on")), "bpm": int(j.get("bpm", 110))})
    except WebSocketDisconnect:
        pass
    finally:
        broadcaster.clients.discard(ws)


# Production mode: serve the built dashboard. Must be mounted last so /api routes win.
if WEB_DIST.is_dir():
    app.mount("/", StaticFiles(directory=WEB_DIST, html=True), name="web")
