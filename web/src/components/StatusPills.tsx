// Quiet source indicators in the header: a small dot + name, green only when live.
import { t } from "../i18n";

export type PillState = "on" | "off" | "warn";

export function StatusPills({ pills }: { pills: { label: string; state: PillState }[] }) {
  return (
    <ul className="sources" aria-label={t("Connections")}>
      {pills.map((p) => (
        <li key={p.label} className={`source ${p.state}`}>
          <span className="source-dot" aria-hidden="true" />
          {p.label}
          <span className="sr-only">{" "}{p.state === "on" ? t("connected") : p.state === "warn" ? t("partly connected") : t("not connected")}</span>
        </li>
      ))}
    </ul>
  );
}
