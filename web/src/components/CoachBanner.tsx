// Alarm bar: the coach's current instruction, in monitor-alarm position under the header.
// Keyed on the rule so each new instruction replays the entrance.
import type { Rule } from "../coach/rules";

export function CoachBanner({ rule, idleText }: { rule: Rule | null; idleText: string }) {
  return (
    <div key={rule?.id ?? "idle"} className={`alarm ${rule ? rule.color : "idle"}`} role="status" aria-live="assertive">
      {rule ? rule.banner : idleText}
    </div>
  );
}
