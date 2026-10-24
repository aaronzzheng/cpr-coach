// Big color-coded banner showing the coach's current top issue.
import type { Rule } from "../coach/rules";

export function CoachBanner({ rule, idleText }: { rule: Rule | null; idleText: string }) {
  return (
    // Keyed on the rule so each new instruction replays the pop-in animation.
    <div key={rule?.id ?? "idle"} className={`banner ${rule ? rule.color : "idle"}`}>
      {rule ? `🗣  ${rule.banner}` : idleText}
    </div>
  );
}
