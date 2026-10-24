"""Dashboard fan-out: tracks /ws clients and pushes a state snapshot at 20 Hz plus events."""

from __future__ import annotations

import asyncio
import contextlib
import logging
from collections.abc import Callable

from fastapi import WebSocket
from pydantic import BaseModel

from .config import BROADCAST_HZ

log = logging.getLogger(__name__)


class Broadcaster:
    def __init__(self) -> None:
        self.clients: set[WebSocket] = set()
        self._task: asyncio.Task[None] | None = None

    async def send(self, msg: BaseModel) -> None:
        if not self.clients:
            return
        text = msg.model_dump_json()
        dead = []
        for ws in list(self.clients):
            try:
                await ws.send_text(text)
            except Exception:  # noqa: BLE001 — any send failure means the client is gone
                dead.append(ws)
        for ws in dead:
            self.clients.discard(ws)

    def start(self, build_state: Callable[[], BaseModel]) -> None:
        async def loop() -> None:
            period = 1.0 / BROADCAST_HZ
            while True:
                try:
                    await self.send(build_state())
                except Exception:
                    log.exception("state broadcast failed")
                await asyncio.sleep(period)

        self._task = asyncio.create_task(loop())

    async def stop(self) -> None:
        if self._task:
            self._task.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await self._task
