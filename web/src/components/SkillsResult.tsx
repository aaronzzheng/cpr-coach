// Skills check result: pass/fail, then each skill with icon + words.
import { BadgeCheck, BadgeX, CircleCheck, CircleX, Minus } from "lucide-react";
import type { Summary } from "../net/api";
import { t } from "../i18n";
import { criteria, criterionPassed, passed } from "../session/skills";

export function SkillsResult({ summary }: { summary: Summary }) {
  const ok = passed(summary);
  const Badge = ok ? BadgeCheck : BadgeX;
  return (
    <section className={`skills ${ok ? "good" : "critical"}`} aria-label={t("Skills check")}>
      <header className="skills-head">
        <Badge size={40} strokeWidth={2} aria-hidden="true" />
        <div>
          <p className="stat-label">{t("Skills check")}</p>
          <p className="skills-verdict">{ok ? t("Passed") : t("Not yet")}</p>
        </div>
      </header>
      <ul className="skills-list">
        {criteria(summary).map((c) => {
          const p = criterionPassed(c);
          const Icon = p === null ? Minus : p ? CircleCheck : CircleX;
          return (
            <li key={c.name} className={p === null ? "na" : p ? "ok" : "bad"}>
              <Icon size={18} strokeWidth={2.25} aria-hidden="true" />
              <span>{t(c.name)}</span>
              <span className="skills-value">{c.value === null ? t("Not measured") : `${Math.round(c.value * 100)}%`}</span>
            </li>
          );
        })}
      </ul>
      <p className="meta">{t("Pass: every measured skill at 80% or better over 2 minutes.")}</p>
    </section>
  );
}
