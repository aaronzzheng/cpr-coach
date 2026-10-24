"""Compiles the watch's CPR1 encoder (apple/Sources/Watch/CPRPacket.swift) for macOS and checks
that the backend decodes its bytes exactly. Skipped where no Swift toolchain is available."""

import shutil
import subprocess
from pathlib import Path

import numpy as np
import pytest

from app.config import REPO_ROOT
from app.ingest import decode_packet

ENCODER = REPO_ROOT / "apple" / "Sources" / "Watch" / "CPRPacket.swift"

MAIN = """
import Foundation
var enc = CPRPacketEncoder()
for i in 0..<20 {
    let t = 1234.5 + Double(i) * 0.01
    enc.append(ts: t, values: (0..<9).map { Float32(i) * 0.1 + Float32($0) })
}
FileHandle.standardOutput.write(enc.flush(seq: 4_000_000_001))
"""


@pytest.mark.skipif(shutil.which("xcrun") is None or not ENCODER.exists(), reason="needs Xcode")
def test_swift_encoder_matches_backend_decoder(tmp_path: Path) -> None:
    main = tmp_path / "main.swift"
    main.write_text(MAIN)
    exe = tmp_path / "enc"
    subprocess.run(["xcrun", "swiftc", "-O", str(ENCODER), str(main), "-o", str(exe)], check=True)
    raw = subprocess.run([str(exe)], check=True, capture_output=True).stdout

    assert len(raw) == 12 + 20 * 44
    pkt = decode_packet(raw)
    assert pkt.seq == 4_000_000_001
    np.testing.assert_allclose(pkt.ts, 1234.5 + np.arange(20) * 0.01)
    expected = np.arange(20)[:, None] * 0.1 + np.arange(9)[None, :]
    np.testing.assert_allclose(np.hstack([pkt.ua, pkt.g, pkt.rr]), expected, rtol=1e-6)
