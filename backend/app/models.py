"""Pydantic message schemas (PRD §7): state and compression events pushed to the dashboard."""

from __future__ import annotations

from typing import Literal

from pydantic import BaseModel


class SessionInfo(BaseModel):
    id: str
    status: Literal["idle", "running", "summary"]
    elapsed_s: float
    cycle_elapsed_s: float
    name: str


class Sources(BaseModel):
    phone_connected: bool
    watch_streaming: bool
    packet_rate_hz: float
    gaps: int
    last_packet_age_ms: int | None
    source: Literal["watch", "sim", "replay", "none"]


class Hr(BaseModel):
    bpm: int | None
    age_s: float | None


class Compressions(BaseModel):
    count: int
    rate_cpm: float | None
    last_depth_cm: float | None
    depth_avg5_cm: float | None  # median of the last 5 depths
    last_t: float | None


class PausesMsg(BaseModel):
    count: int
    longest_s: float
    hands_off_s: float
    ccf: float | None
    in_pause: bool
    pause_elapsed_s: float


class Fatigue(BaseModel):
    score: float
    baseline_depth_cm: float | None
    recent_depth_cm: float | None
    swap_recommended: bool


class Wave(BaseModel):
    t0: float
    fs: float
    a_up: list[float]


class StateMsg(BaseModel):
    type: Literal["state"] = "state"
    ts: float
    session: SessionInfo
    sources: Sources
    hr: Hr
    compressions: Compressions
    pauses: PausesMsg
    fatigue: Fatigue
    wave: Wave


class CompressionMsg(BaseModel):
    type: Literal["compression"] = "compression"
    t: float
    interval_s: float | None
    inst_rate_cpm: float | None
    depth_cm: float | None
    rate_ok: bool
    depth_ok: bool | None
