from fastapi.testclient import TestClient

from app.main import app


def test_health_ok() -> None:
    r = TestClient(app).get("/api/health")
    assert r.status_code == 200
    assert r.json()["ok"] is True


def test_targets_loaded() -> None:
    r = TestClient(app).get("/api/targets")
    assert r.json()["rate_target_cpm"] == 110
