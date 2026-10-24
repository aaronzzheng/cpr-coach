// Posture checklist row: elbows, alignment, recoil, plus heart rate when the watch provides it.
import type { LiveState } from "../fusion/fuse";

type Status = "ok" | "warn" | "na";
const ICON: Record<Status, string> = { ok: "✅", warn: "⚠️", na: "—" };

function Item({ label, status }: { label: string; status: Status }) {
  return (
    <span className={`check ${status}`}>
      <span className="check-icon">{ICON[status]}</span>
      {label}
    </span>
  );
}

export function PostureChecklist({ live }: { live: LiveState }) {
  const p = live.posture;
  const s = (violation: boolean): Status => (!p.available ? "na" : violation ? "warn" : "ok");
  return (
    <div className="checklist">
      <Item label="Elbows locked" status={s(p.elbowViolation)} />
      <Item label="Shoulders over hands" status={s(p.alignViolation)} />
      <Item label="Full recoil" status={p.incompleteRecoil === null ? "na" : p.incompleteRecoil ? "warn" : "ok"} />
      <span className="check hr">❤️ {live.hrBpm === null ? "—" : `${live.hrBpm} bpm`}</span>
    </div>
  );
}
