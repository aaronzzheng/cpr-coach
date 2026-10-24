// Posture strip: form checks from the camera, then heart rate and a segmented fatigue bar.
import type { LiveState } from "../fusion/fuse";

type Status = "ok" | "warn" | "na";
const GLYPH: Record<Status, string> = { ok: "✓", warn: "!", na: "–" };
const FATIGUE_SEGMENTS = 10;

function Check({ label, status }: { label: string; status: Status }) {
  return (
    <span className={`check ${status}`}>
      <span className="check-glyph" aria-hidden="true">
        {GLYPH[status]}
      </span>
      {label}
      <span className="sr-only">{status === "ok" ? " good" : status === "warn" ? " needs attention" : " not measured"}</span>
    </span>
  );
}

export function PostureChecklist({ live }: { live: LiveState }) {
  const p = live.posture;
  const s = (violation: boolean): Status => (!p.available ? "na" : violation ? "warn" : "ok");
  const lit = Math.round((live.fatigueScore ?? 0) * FATIGUE_SEGMENTS);
  return (
    <div className="strip">
      <Check label="Elbows locked" status={s(p.elbowViolation)} />
      <Check label="Shoulders over hands" status={s(p.alignViolation)} />
      <Check label="Full recoil" status={p.incompleteRecoil === null ? "na" : p.incompleteRecoil ? "warn" : "ok"} />
      <span className="strip-hr" aria-label="Heart rate">
        <span className="strip-hr-label">HR</span>
        <span className="strip-hr-value">{live.hrBpm ?? "—"}</span>
      </span>
      <span className={`strip-fatigue ${live.fatigueScore === null ? "na" : ""}`} aria-label={`Fatigue ${Math.round((live.fatigueScore ?? 0) * 100)}%`}>
        Fatigue
        <span className="segments" aria-hidden="true">
          {Array.from({ length: FATIGUE_SEGMENTS }, (_, i) => (
            <span key={i} className={i < lit ? (i >= 7 ? "on high" : "on") : ""} />
          ))}
        </span>
      </span>
    </div>
  );
}
