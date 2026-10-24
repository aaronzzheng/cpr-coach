// Dashboard language: one choice drives the screen, the coach's voice and voice commands. English
// strings are the keys (as on the phone); translations.json holds the other languages and is
// generated from the same sources as apple/Sources/Core/Translations.swift.
import table from "./translations.json";

export const LANGS = ["en", "es", "fr", "zh", "ko", "ja", "hi"] as const;
export type Lang = (typeof LANGS)[number];

export const LANG_INFO: Record<Lang, { name: string; bcp47: string }> = {
  en: { name: "English", bcp47: "en-US" },
  es: { name: "Español", bcp47: "es-ES" },
  fr: { name: "Français", bcp47: "fr-FR" },
  zh: { name: "中文", bcp47: "zh-CN" },
  ko: { name: "한국어", bcp47: "ko-KR" },
  ja: { name: "日本語", bcp47: "ja-JP" },
  hi: { name: "हिन्दी", bcp47: "hi-IN" },
};

const translations = table as Record<string, Partial<Record<Lang, string>>>;
const KEY = "cprcoach.lang";

function initial(): Lang {
  try {
    const saved = localStorage.getItem(KEY);
    if (saved && (LANGS as readonly string[]).includes(saved)) return saved as Lang;
  } catch {
    // storage blocked: fall through to the browser language
  }
  const code = (navigator.language || "en").slice(0, 2);
  return (LANGS as readonly string[]).includes(code) ? (code as Lang) : "en";
}

let current: Lang = initial();

export function lang(): Lang {
  return current;
}

export function setLang(l: Lang): void {
  current = l;
  document.documentElement.lang = LANG_INFO[l].bcp47;
  try {
    localStorage.setItem(KEY, l);
  } catch {
    // per-viewer convenience only
  }
}

/** Translate an English string, then fill `%@` placeholders in order. */
export function t(english: string, ...args: (string | number)[]): string {
  let s = current === "en" ? english : (translations[english]?.[current] ?? english);
  for (const a of args) {
    const i = s.indexOf("%@");
    if (i < 0) break;
    s = s.slice(0, i) + String(a) + s.slice(i + 2);
  }
  return s;
}

/** A decimal in the current language's style. */
export function num(x: number, digits: number): string {
  return x.toLocaleString(LANG_INFO[current].bcp47, { minimumFractionDigits: digits, maximumFractionDigits: digits });
}
