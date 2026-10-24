// Form checks from the camera, each an icon + words (never colour alone), and a fatigue meter.
import { CircleCheck, Minus, TriangleAlert } from "lucide-react";
import type { LiveState } from "../fusion/fuse";

type Status = "ok" | "warn" | "na";

function Check({ label, status }: { label: string; status: Status }) {
  const Icon = status === "ok" ? CircleCheck : status === "warn" ? TriangleAlert : Minus;
  return (
    <li className={`check ${status}`}>
      <Icon size={20} strokeWidth={2.25} aria-hidden="true" />
      <span>{label}</span>
      <span className="sr-only">{status === "ok" ? ": good" : status === "warn" ? ": fix this" : ": not measured"}</span>
    </li>
  );
}

export function PostureChecklist({ live }: { live: LiveState }) {
  const p = live.posture;
  const s = (violation: boolean): Status => (!p.available ? "na" : violation ? "warn" : "ok");
  const fatigue = live.fatigueScore;
  return (
    <div className="strip">
      <ul className="checks" aria-label="Form">
        <Check label="Elbows locked" status={s(p.elbowViolation)} />
        <Check label="Shoulders over hands" status={s(p.alignViolation)} />
        <Check label="Full recoil" status={p.incompleteRecoil === null ? "na" : p.incompleteRecoil ? "warn" : "ok"} />
      </ul>
      <div className="fatigue">
        <span className="fatigue-label">Fatigue</span>
        <div className="meter small" role="meter" aria-valuemin={0} aria-valuemax={100} aria-valuenow={fatigue === null ? undefined : Math.round(fatigue * 100)} aria-label="Fatigue">
          {fatigue !== null && <div className={`meter-fill ${fatigue >= 0.7 ? "swap" : fatigue >= 0.4 ? "warn" : "ok"}`} style={{ width: `${Math.max(2, fatigue * 100)}%` }} />}
        </div>
        <span className="fatigue-value">{fatigue === null ? "—" : `${Math.round(fatigue * 100)}%`}</span>
      </div>
    </div>
  );
}
