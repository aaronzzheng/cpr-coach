"""End-to-end through the HTTP and WebSocket API: start, stream simulated watch data, stop,
post camera metrics, add to the leaderboard, and replay the recording."""

from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app import main
from app.ingest import FRAME_IMU, encode_packet
from app.pipeline import WatchPipeline
from app.session import Session
from app.store import Store
from tools.replay import load
from tools.synth import SynthWatch


@pytest.fixture
def client(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setattr(main, "store", Store(tmp_path))
    monkeypatch.setattr(main, "pipeline", WatchPipeline())
    monkeypatch.setattr(main, "session", Session())
    with TestClient(main.app) as c:
        yield c


def _stream(client: TestClient, seconds: float, depth: float = 5.5) -> None:
    synth = SynthWatch(rate_cpm=110, depth_cm=depth, seed=9)
    with client.websocket_connect("/ingest") as ws:
        ws.send_text('{"t":"hello","device":"sim"}')
        ws.send_text('{"t":"hr","bpm":95,"ts":1.0}')
        for seq in range(int(seconds * 5)):
            ts, ua, g, rr, _ = synth.next(20)
            ws.send_bytes(bytes([FRAME_IMU]) + encode_packet(seq, ts, ua, g, rr))


def test_full_session_flow(client: TestClient, tmp_path: Path) -> None:
    sid = client.post("/api/session/start", json={"name": "Judge Alice"}).json()["session_id"]
    _stream(client, 20)
    watch = client.post("/api/session/stop").json()
    assert watch["compressions"] >= 15
    assert watch["rate_pct"] > 0.9

    summary = client.post(f"/api/session/{sid}/summary", json={"elbow_pct": 1.0, "align_pct": 1.0}).json()
    assert summary["source"] == "watch"
    assert summary["name"] == "Judge Alice"
    assert 0 <= summary["score"] <= 100
    assert client.get(f"/api/session/{sid}/summary").json()["score"] == summary["score"]

    board = client.post("/api/leaderboard", json={"session_id": sid}).json()
    assert board[0]["name"] == "Judge Alice"
    assert client.get("/api/leaderboard").json() == board

    frames = load(tmp_path / "sessions" / sid)
    assert sum(isinstance(f, bytes) for _, f in frames) == 100
    assert any(isinstance(f, str) and '"hr"' in f for _, f in frames)


def test_stop_without_session_is_409(client: TestClient) -> None:
    assert client.post("/api/session/stop").status_code == 409


def test_calibration_applies_to_pipeline(client: TestClient) -> None:
    assert client.post("/api/calibration", json={"depth_scale": 1.25}).json()["depth_scale"] == 1.25
    assert main.pipeline.detector.depth_scale == 1.25
    assert client.post("/api/calibration", json={"depth_scale": 5}).status_code == 422
