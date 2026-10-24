"""FastAPI entry point: HTTP routes, websockets, and static serving of the built dashboard."""

from __future__ import annotations

import time

from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles

from .config import TARGETS, WEB_DIST

app = FastAPI(title="CPR Coach")
STARTED_AT = time.time()


@app.get("/api/health")
def health() -> dict:
    return {
        "ok": True,
        "uptime_s": round(time.time() - STARTED_AT, 1),
        "sources": {
            "phone_connected": False,
            "watch_streaming": False,
            "source": "none",
        },
    }


@app.get("/api/targets")
def targets() -> dict:
    return TARGETS


# Production mode: serve the built dashboard. Must be mounted last so /api routes win.
if WEB_DIST.is_dir():
    app.mount("/", StaticFiles(directory=WEB_DIST, html=True), name="web")
