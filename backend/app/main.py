"""FastAPI entry point: HTTP routes, the phone/simulator /ingest socket, the dashboard /ws
socket, and static serving of the built dashboard."""

from __future__ import annotations

import json
import logging
import time
from collections import deque
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from datetime import datetime

from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

from . import models as m
from .broadcaster import Broadcaster
from .config import DATA_DIR, SOURCE_STALE_S, TARGETS, WAVE_FS, WEB_DIST
from .dsp.compressions import Compression
from .ingest import FRAME_IMU, decode_packet
from .pipeline import WatchPipeline
from .recorder import Recorder
from .session import CameraMetrics, Session, build_summary
from .store import Store

log = logging.getLogger("cpr")

STARTED_AT = time.time()
store = Store(DATA_DIR)
pipeline = WatchPipeline(depth_scale=store.calibration()["depth_scale"])
session = Session()
broadcaster = Broadcaster()
recorder = Recorder()
# Watch half of the summary for the most recently stopped session, until the dashboard posts its half.
pending_watch: dict[str, dict] = {}


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
        source = {"iphone": "watch", "sim": "sim", "replay": "replay"}.get(
            ingest.device, "watch"
        )
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
            last_packet_age_ms=None
            if ingest.last_packet is None
            else int((now - ingest.last_packet) * 1000),
            watch_reachable=ingest.watch_reachable if ingest.ws is not None else None,
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
    rate_ok = (
        c.inst_rate_cpm is not None
        and TARGETS["rate_min_cpm"] <= c.inst_rate_cpm <= TARGETS["rate_max_cpm"]
    )
    lo, hi = session.depth_range
    depth_ok = None if c.depth_cm is None else lo <= c.depth_cm <= hi
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
            "watch_reachable": ingest.watch_reachable
            if ingest.ws is not None
            else None,
            "source": ingest.device if ingest.ws is not None else "none",
        },
    }


@app.get("/api/targets")
def targets() -> dict:
    return TARGETS


class StartBody(BaseModel):
    name: str = ""
    patient: str = "adult"


async def start_session(name: str, patient: str = "adult") -> dict:
    now = time.time()
    session.start(now, name.strip(), patient)
    pipeline.swap()
    recorder.start(
        store.sessions_dir / session.id,
        {"session_id": session.id, "name": session.name, "t0": now},
    )
    await ingest.send_cmd({"cmd": "start"})
    return {"session_id": session.id}


async def stop_session() -> dict:
    now = time.time()
    if session.status != "running":
        raise HTTPException(409, "no session running")
    session.stop(now)
    recorder.stop()
    # Deliberately no "stop" to the watch: it can only receive commands while its app is in the
    # foreground, so a stopped watch would miss the next session's "start". Leave it streaming.
    watch = session.watch_metrics(now)
    pending_watch[session.id] = watch
    return watch


@app.post("/api/session/start")
async def api_start(body: StartBody) -> dict:
    return await start_session(body.name, body.patient)


@app.post("/api/session/stop")
async def api_stop() -> dict:
    return await stop_session()


@app.post("/api/session/{session_id}/summary")
def api_post_summary(session_id: str, cam: CameraMetrics) -> dict:
    watch = pending_watch.pop(session_id, None)
    if watch is None:
        raise HTTPException(404, "unknown or already summarized session")
    summary = build_summary(watch, cam, datetime.now().isoformat(timespec="seconds"))
    store.save_summary(summary)
    session.status = "idle"
    return summary


@app.get("/api/session/{session_id}/summary")
def api_get_summary(session_id: str) -> dict:
    summary = store.summary(session_id)
    if summary is None:
        raise HTTPException(404, "no summary")
    return summary


class LeaderboardBody(BaseModel):
    session_id: str
    name: str | None = None


@app.get("/api/leaderboard")
def api_leaderboard() -> list[dict]:
    return store.leaderboard()


@app.post("/api/leaderboard")
def api_add_leaderboard(body: LeaderboardBody) -> list[dict]:
    summary = store.summary(body.session_id)
    if summary is None:
        raise HTTPException(404, "no summary for that session")
    return store.add_to_leaderboard(summary, body.name)


class CalibrationBody(BaseModel):
    depth_scale: float | None = None
    cm_per_px: float | None = None


@app.get("/api/calibration")
def api_get_calibration() -> dict:
    return store.calibration()


@app.post("/api/calibration")
def api_set_calibration(body: CalibrationBody) -> dict:
    try:
        c = store.save_calibration(body.depth_scale, body.cm_per_px)
    except ValueError as e:
        raise HTTPException(422, str(e)) from e
    pipeline.set_depth_scale(c["depth_scale"])
    return c


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
                recorder.imu(now, data[1:])
                out = pipeline.process(pkt, now)
                for c in out.bottoms:
                    session.on_compression(c.t)
                for c in out.completed:
                    cm = compression_msg(c)
                    session.on_graded(
                        c.t, c.inst_rate_cpm, cm.rate_ok, c.depth_cm, cm.depth_ok
                    )
                    recorder.compression(now, cm.model_dump())
                    await broadcaster.send(cm)
                if (
                    pipeline.fatigue_state().swap_recommended
                    and pipeline.last_ts is not None
                ):
                    # Packet time, not arrival time, so replays at other speeds place it correctly.
                    session.mark_fatigue(pipeline.to_laptop(pipeline.last_ts))
            elif msg.get("text"):
                j = json.loads(msg["text"])
                recorder.text(now, j)
                t = j.get("t")
                if t == "hello":
                    ingest.device = j.get("device", "unknown")
                    # New sender, new clock: start DSP and the clock mapping fresh.
                    pipeline.reset_dsp()
                    pipeline.seq.reset()
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
                await start_session(j.get("name", ""), j.get("patient", "adult"))
            elif cmd == "stop" and session.status == "running":
                await stop_session()
            elif cmd == "swap":
                pipeline.swap()
            elif cmd == "planned_pause":
                session.planned_pause = True
            elif cmd == "metronome":
                await ingest.send_cmd(
                    {
                        "cmd": "metronome",
                        "on": bool(j.get("on")),
                        "bpm": int(j.get("bpm", 110)),
                    }
                )
    except WebSocketDisconnect:
        pass
    finally:
        broadcaster.clients.discard(ws)


# Production mode: serve the built dashboard. Must be mounted last so /api routes win.
if WEB_DIST.is_dir():
    app.mount("/", StaticFiles(directory=WEB_DIST, html=True), name="web")
