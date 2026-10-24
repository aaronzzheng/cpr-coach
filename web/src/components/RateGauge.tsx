// Arc gauge for compression rate (80–140/min) with the AHA green zone.
import { TARGETS } from "../config";
import type { Source } from "../fusion/fuse";

const MIN = 80;
const MAX = 140;
const SWEEP = 240;
const R = 120;
const CX = 150;
const CY = 150;

/** Degrees clockwise from 12 o'clock for a rate value. */
function angle(v: number): number {
  const clamped = Math.min(MAX, Math.max(MIN, v));
  return -SWEEP / 2 + ((clamped - MIN) / (MAX - MIN)) * SWEEP;
}

function polar(v: number): [number, number] {
  const a = (angle(v) * Math.PI) / 180;
  return [CX + R * Math.sin(a), CY - R * Math.cos(a)];
}

function arc(from: number, to: number): string {
  const [x0, y0] = polar(from);
  const [x1, y1] = polar(to);
  const large = ((to - from) / (MAX - MIN)) * SWEEP > 180 ? 1 : 0;
  return `M ${x0} ${y0} A ${R} ${R} 0 ${large} 1 ${x1} ${y1}`;
}

export function RateGauge({ cpm, source }: { cpm: number | null; source: Source }) {
  const ok = cpm !== null && cpm >= TARGETS.rate_min_cpm && cpm <= TARGETS.rate_max_cpm;
  return (
    <div className="metric">
      <div className="metric-label">RATE</div>
      <svg viewBox="0 0 300 260" className="gauge">
        <path d={arc(MIN, MAX)} className="gauge-track" />
        <path d={arc(TARGETS.rate_min_cpm, TARGETS.rate_max_cpm)} className="gauge-zone" />
        {/* Rotated rather than re-pointed so the CSS transition can sweep it smoothly. */}
        <line
          x1={CX}
          y1={CY}
          x2={CX}
          y2={CY - R + 14}
          className={`gauge-needle ${cpm === null ? "idle" : ""}`}
          style={{ transform: `rotate(${angle(cpm ?? MIN)}deg)`, transformOrigin: `${CX}px ${CY}px` }}
        />
        <circle cx={CX} cy={CY} r={8} className="gauge-hub" />
        <text x={CX} y={CY + 70} className={`gauge-value ${cpm === null ? "" : ok ? "good" : "bad"}`}>
          {cpm === null ? "—" : Math.round(cpm)}
        </text>
        <text x={CX} y={CY + 100} className="gauge-unit">
          /min
        </text>
      </svg>
      <div className="metric-source">{source ? `via ${source}` : "no signal"}</div>
    </div>
  );
}
