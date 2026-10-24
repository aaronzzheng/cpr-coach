// Web Speech API wrapper: one voice in the dashboard's language, interrupts only for a
// higher-priority line, mutable. Exposes an echo window so voice commands ignore the coach.
import { SPEECH } from "../config";
import { LANG_INFO, lang } from "../i18n";

export class Speech {
  muted = false;
  private voice: SpeechSynthesisVoice | null = null;
  private currentPriority: number | null = null;
  private lastEnd = 0;

  constructor() {
    if (typeof speechSynthesis === "undefined") return;
    this.pick();
    speechSynthesis.addEventListener("voiceschanged", () => this.pick());
  }

  /** Re-pick the voice for the current language. */
  pick(): void {
    if (typeof speechSynthesis === "undefined") return;
    const want = LANG_INFO[lang()].bcp47;
    const prefix = want.slice(0, 2);
    const voices = speechSynthesis.getVoices().filter((v) => v.lang.replace("_", "-").startsWith(prefix));
    this.voice =
      voices.find((v) => v.localService && v.lang.replace("_", "-") === want) ?? voices.find((v) => v.localService) ?? voices[0] ?? null;
  }

  /** The coach is talking, or just stopped (recognition lags speech). */
  get echoWindow(): boolean {
    return (typeof speechSynthesis !== "undefined" && speechSynthesis.speaking) || performance.now() - this.lastEnd < 1200;
  }

  /** Lower `priority` number = more important. */
  say(text: string, priority: number): void {
    if (this.muted || typeof speechSynthesis === "undefined") return;
    if (speechSynthesis.speaking) {
      if (this.currentPriority !== null && priority >= this.currentPriority) return;
      speechSynthesis.cancel();
    }
    const u = new SpeechSynthesisUtterance(text);
    if (this.voice) u.voice = this.voice;
    u.lang = LANG_INFO[lang()].bcp47;
    u.rate = lang() === "en" ? SPEECH.rate : 1;
    u.onend = () => {
      this.currentPriority = null;
      this.lastEnd = performance.now();
    };
    this.currentPriority = priority;
    speechSynthesis.speak(u);
  }

  setMuted(m: boolean): void {
    this.muted = m;
    if (m && typeof speechSynthesis !== "undefined") speechSynthesis.cancel();
  }
}
