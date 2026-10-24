// Monitor-style sweep: faint grid, the last few seconds of compression motion in trace green,
// and a tick per detected compression.
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
    const css = getComputedStyle(cv);
    const gridColor = css.getPropertyValue("--grid").trim() || "#12181d";
    const traceColor = css.getPropertyValue("--trace").trim() || "#3ddc84";
    g.strokeStyle = gridColor;
    g.lineWidth = 1;
    const cell = 24 * devicePixelRatio;
    for (let gx = w % cell; gx < w; gx += cell) {
      g.beginPath();
      g.moveTo(gx, 0);
      g.lineTo(gx, h);
      g.stroke();
    }
    for (let gy = h % cell; gy < h; gy += cell) {
      g.beginPath();
      g.moveTo(0, gy);
      g.lineTo(w, gy);
      g.stroke();
    }

    if (samples.length < 2) return;

    const vs = samples.map((s) => s.v);
    const lo = Math.min(...vs);
    const hi = Math.max(...vs);
    const range = Math.max(hi - lo, 1e-6);
    const pad = h * 0.12;
    const x = (t: number) => w - ((now - t) / spanS) * w;
    const y = (v: number) => pad + ((v - lo) / range) * (h - 2 * pad);

    g.strokeStyle = "rgba(233,238,242,0.35)";
    g.lineWidth = 2 * devicePixelRatio;
    for (const t of ticks) {
      g.beginPath();
      g.moveTo(x(t), h - pad / 2);
      g.lineTo(x(t), h);
      g.stroke();
    }

    g.strokeStyle = traceColor;
    g.lineWidth = 2.5 * devicePixelRatio;
    g.lineJoin = "round";
    g.beginPath();
    samples.forEach((s, i) => (i ? g.lineTo(x(s.t), y(s.v)) : g.moveTo(x(s.t), y(s.v))));
    g.stroke();
  });

  return <canvas ref={ref} className="waveform" />;
}
