// Scrolling trace of the last few seconds of compression motion, with a tick per compression.
import { useEffect, useRef } from "react";

export interface WaveSample {
  t: number;
  v: number;
}

/** `samples` should grow downward-positive (deeper = larger). */
export function Waveform({ samples, ticks, now, spanS }: { samples: WaveSample[]; ticks: number[]; now: number; spanS: number }) {
  const ref = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const cv = ref.current;
    if (!cv) return;
    const w = cv.clientWidth * devicePixelRatio;
    const h = cv.clientHeight * devicePixelRatio;
    if (cv.width !== w || cv.height !== h) {
      cv.width = w;
      cv.height = h;
    }
    const g = cv.getContext("2d");
    if (!g) return;
    g.clearRect(0, 0, w, h);
    if (samples.length < 2) return;

    const vs = samples.map((s) => s.v);
    const lo = Math.min(...vs);
    const hi = Math.max(...vs);
    const range = Math.max(hi - lo, 1e-6);
    const pad = h * 0.12;
    const x = (t: number) => w - ((now - t) / spanS) * w;
    const y = (v: number) => pad + ((v - lo) / range) * (h - 2 * pad);

    g.strokeStyle = "rgba(125,138,153,0.5)";
    g.lineWidth = 2 * devicePixelRatio;
    for (const t of ticks) {
      g.beginPath();
      g.moveTo(x(t), h - pad / 2);
      g.lineTo(x(t), h);
      g.stroke();
    }

    g.strokeStyle = "#38bdf8";
    g.lineWidth = 3 * devicePixelRatio;
    g.beginPath();
    samples.forEach((s, i) => (i ? g.lineTo(x(s.t), y(s.v)) : g.moveTo(x(s.t), y(s.v))));
    g.stroke();
  });

  return <canvas ref={ref} className="waveform" />;
}
