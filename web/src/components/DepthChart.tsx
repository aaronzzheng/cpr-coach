// Depth over time for the summary, with the AHA green band and the fatigue moment.
import { TARGETS } from "../config";

/** Lift the pen across pauses so hands-off time doesn't look like steady depth. */
const BREAK_S = TARGETS.pause_threshold_s;

const W = 640;
const H = 200;
const PAD = { l: 36, r: 12, t: 12, b: 26 };
const MAX_CM = 8;

export function DepthChart({ series, fatigueAt }: { series: [number, number][]; fatigueAt: number | null }) {
  if (series.length < 2) return <div className="chart-empty">No depth data</div>;
  const maxT = Math.max(...series.map(([t]) => t), fatigueAt ?? 0, 1);
  const x = (t: number) => PAD.l + (t / maxT) * (W - PAD.l - PAD.r);
  const y = (cm: number) => PAD.t + (1 - Math.min(cm, MAX_CM) / MAX_CM) * (H - PAD.t - PAD.b);
  const path = series
    .map(([t, d], i) => `${i && t - series[i - 1][0] <= BREAK_S ? "L" : "M"}${x(t).toFixed(1)},${y(d).toFixed(1)}`)
    .join(" ");
  const ticks = Array.from({ length: 5 }, (_, i) => Math.round((maxT * i) / 4));

  return (
    <svg viewBox={`0 0 ${W} ${H}`} className="depth-chart">
      <rect
        x={PAD.l}
        width={W - PAD.l - PAD.r}
        y={y(TARGETS.depth_max_cm)}
        height={y(TARGETS.depth_min_cm) - y(TARGETS.depth_max_cm)}
        className="chart-band"
      />
      {[0, 2, 4, 6, 8].map((cm) => (
        <g key={cm}>
          <line x1={PAD.l} x2={W - PAD.r} y1={y(cm)} y2={y(cm)} className="chart-grid" />
          <text x={PAD.l - 6} y={y(cm) + 4} className="chart-axis" textAnchor="end">
            {cm}
          </text>
        </g>
      ))}
      {ticks.map((t) => (
        <text key={t} x={x(t)} y={H - 6} className="chart-axis" textAnchor="middle">
          {t}s
        </text>
      ))}
      <path d={path} className="chart-line" />
      {fatigueAt !== null && (
        <g>
          <line x1={x(fatigueAt)} x2={x(fatigueAt)} y1={PAD.t} y2={H - PAD.b} className="chart-fatigue" />
          {/* Label on whichever side of the marker has room. */}
          <text
            x={x(fatigueAt) + (x(fatigueAt) > W * 0.7 ? -6 : 6)}
            y={PAD.t + 14}
            textAnchor={x(fatigueAt) > W * 0.7 ? "end" : "start"}
            className="chart-fatigue-label"
          >
            fatigue detected
          </text>
        </g>
      )}
    </svg>
  );
}
