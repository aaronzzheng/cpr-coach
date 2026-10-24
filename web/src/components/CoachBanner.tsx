// Big color-coded banner showing the coach's current top issue.
import type { Rule } from "../coach/rules";

export function CoachBanner({ rule, idleText }: { rule: Rule | null; idleText: string }) {
  return (
    <div className={`banner ${rule ? rule.color : "idle"}`}>
      {rule ? `🗣  ${rule.banner}` : idleText}
    </div>
  );
}
