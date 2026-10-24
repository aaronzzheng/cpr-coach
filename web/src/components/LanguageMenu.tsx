// Language picker: switches the screen, the coach's voice and voice commands together.
import { Globe } from "lucide-react";
import { LANG_INFO, LANGS, type Lang, t } from "../i18n";

export function LanguageMenu({ value, onChange }: { value: Lang; onChange: (l: Lang) => void }) {
  return (
    <label className="lang-menu" title={t("Language")}>
      <Globe size={18} aria-hidden="true" />
      <span className="sr-only">{t("Language")}</span>
      <select value={value} onChange={(e) => onChange(e.target.value as Lang)}>
        {LANGS.map((l) => (
          <option key={l} value={l}>
            {LANG_INFO[l].name}
          </option>
        ))}
      </select>
    </label>
  );
}
