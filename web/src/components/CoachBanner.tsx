// The hero: the coach's current instruction in large type, with a status icon on a soft tint of
// the status colour (never a saturated slab), plus one line of specifics underneath.
import { CircleAlert, CircleCheck, Repeat2, TriangleAlert, type LucideIcon } from "lucide-react";
import type { Rule } from "../coach/rules";
import { t } from "../i18n";

const TONE: Record<Rule["color"], { cls: string; Icon: LucideIcon; word: string }> = {
  red: { cls: "critical", Icon: CircleAlert, word: "Act now" },
  amber: { cls: "warn", Icon: TriangleAlert, word: "Adjust" },
  purple: { cls: "swap", Icon: Repeat2, word: "Swap" },
  green: { cls: "good", Icon: CircleCheck, word: "Good" },
};

export function CoachBanner({ rule, idleText, detail }: { rule: Rule | null; idleText: string; detail?: string | null }) {
  const tone = rule ? TONE[rule.color] : null;
  return (
    <div key={rule?.id ?? idleText} className={`instruction ${tone?.cls ?? "idle"}`} role="status" aria-live="assertive">
      {tone && (
        <span className="instruction-icon">
          <tone.Icon size={44} strokeWidth={2.25} aria-hidden="true" />
          <span className="sr-only">{t(tone.word)}: </span>
        </span>
      )}
      <span className="instruction-text">
        <span className="instruction-title">{rule ? t(rule.banner) : idleText}</span>
        {detail && <span className="instruction-detail">{detail}</span>}
      </span>
    </div>
  );
}
