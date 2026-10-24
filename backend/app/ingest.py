"""Phone/simulator frames: decode CPR1 IMU packets and track seq gaps.

Binary frame = 0x01 + packet. Packet header (little-endian): magic u32 "CPR1", seq u32,
count u16, reserved u16; then `count` rows of ts f64 + 9 × f32 (ua xyz, gravity xyz, rotation xyz).
"""

from __future__ import annotations

import struct
from dataclasses import dataclass

import numpy as np

FRAME_IMU = 0x01
MAGIC = 0x43505231
HEADER = struct.Struct("<IIHH")
ROW_DTYPE = np.dtype([("ts", "<f8"), ("v", "<f4", (9,))])


@dataclass
class ImuPacket:
    seq: int
    ts: np.ndarray  # (n,) seconds since watch boot
    ua: np.ndarray  # (n, 3) g, gravity removed
    g: np.ndarray  # (n, 3) g
    rr: np.ndarray  # (n, 3) rad/s


def encode_packet(seq: int, ts: np.ndarray, ua: np.ndarray, g: np.ndarray, rr: np.ndarray) -> bytes:
    rows = np.empty(len(ts), dtype=ROW_DTYPE)
    rows["ts"] = ts
    rows["v"] = np.hstack([ua, g, rr]).astype("<f4")
    return HEADER.pack(MAGIC, seq & 0xFFFFFFFF, len(ts), 0) + rows.tobytes()


def decode_packet(data: bytes) -> ImuPacket:
    if len(data) < HEADER.size:
        raise ValueError("packet too short")
    magic, seq, count, _ = HEADER.unpack_from(data)
    if magic != MAGIC:
        raise ValueError(f"bad magic {magic:#x}")
    expected = HEADER.size + count * ROW_DTYPE.itemsize
    if len(data) != expected:
        raise ValueError(f"length {len(data)} != {expected} for {count} rows")
    rows = np.frombuffer(data, dtype=ROW_DTYPE, count=count, offset=HEADER.size)
    v = rows["v"].astype(np.float64)
    return ImuPacket(seq=seq, ts=rows["ts"].astype(np.float64), ua=v[:, 0:3], g=v[:, 3:6], rr=v[:, 6:9])


class SeqTracker:
    """Counts missing batches. Returns True from `check` when this packet follows a gap."""

    def __init__(self) -> None:
        self.last: int | None = None
        self.gaps = 0

    def reset(self) -> None:
        self.last = None

    def check(self, seq: int) -> bool:
        if self.last is None:
            self.last = seq
            return False
        missing = (seq - self.last - 1) & 0xFFFFFFFF
        restarted = missing > 0x7FFFFFFF  # seq went backwards: sender restarted
        if missing and not restarted:
            self.gaps += missing
        self.last = seq
        return missing != 0
