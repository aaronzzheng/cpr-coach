import numpy as np
import pytest

from app.ingest import ImuPacket, SeqTracker, decode_packet, encode_packet
from tests.helpers import run_pipeline
from tools.synth import SynthWatch


def test_rate_and_count_at_110() -> None:
    p, bottoms, _ = run_pipeline(SynthWatch(rate_cpm=110, depth_cm=5.5, noise=0.3, seed=1), 30)
    assert abs(p.detector.rate_cpm - 110) <= 2
    assert abs(len(bottoms) - 55) <= 1


@pytest.mark.parametrize("cpm", [80, 90, 100, 110, 120, 130, 140])
def test_rate_sweep(cpm: int) -> None:
    p, _, _ = run_pipeline(SynthWatch(rate_cpm=cpm, depth_cm=5.5, noise=0.3, seed=cpm), 20)
    assert abs(p.detector.rate_cpm - cpm) <= 3


def test_packet_roundtrip() -> None:
    ts, ua, g, rr, _ = SynthWatch().next(20)
    raw = encode_packet(7, ts, ua, g, rr)
    assert len(raw) == 12 + 20 * 44
    pkt = decode_packet(raw)
    assert pkt.seq == 7
    np.testing.assert_allclose(pkt.ts, ts)
    np.testing.assert_allclose(pkt.ua, ua, atol=1e-6)


def test_bad_packets_rejected() -> None:
    with pytest.raises(ValueError):
        decode_packet(b"\x00" * 12)
    ts, ua, g, rr, _ = SynthWatch().next(20)
    with pytest.raises(ValueError):
        decode_packet(encode_packet(1, ts, ua, g, rr)[:-4])


def test_seq_tracker() -> None:
    s = SeqTracker()
    assert [s.check(i) for i in (0, 1, 2, 5, 6)] == [False, False, False, True, False]
    assert s.gaps == 2
    assert s.check(0) is True  # restart counts as a discontinuity, not 4 billion gaps
    assert s.gaps == 2


def test_dropped_batch_no_crash_no_bogus_depth() -> None:
    p, bottoms, done = run_pipeline(SynthWatch(rate_cpm=110, depth_cm=5.5, seed=4), 30, drop={50, 51, 90})
    assert p.seq.gaps == 3
    depths = [c.depth_cm for c in done if c.depth_cm is not None]
    assert depths, "should still produce depths away from the gaps"
    assert all(4.5 <= d <= 6.5 for d in depths), depths
    assert abs(len(bottoms) - 55) <= 3


def test_unused_packet_type() -> None:
    p, _, _ = run_pipeline(SynthWatch(), 0.2)
    out = p.process(ImuPacket(99, np.empty(0), np.empty((0, 3)), np.empty((0, 3)), np.empty((0, 3))), 0.0)
    assert out.bottoms == []
