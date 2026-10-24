// Web Speech API wrapper: one English voice, interrupts only for a higher-priority line, mutable.
import { SPEECH } from "../config";

export class Speech {
  muted = false;
  private voice: SpeechSynthesisVoice | null = null;
  private currentPriority: number | null = null;

  constructor() {
    if (typeof speechSynthesis === "undefined") return;
    const pick = () => {
      const voices = speechSynthesis.getVoices().filter((v) => v.lang.startsWith(SPEECH.lang));
      this.voice =
        voices.find((v) => v.localService && v.lang === "en-US") ?? voices.find((v) => v.localService) ?? voices[0] ?? null;
    };
    pick();
    speechSynthesis.addEventListener("voiceschanged", pick);
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
    u.rate = SPEECH.rate;
    u.onend = () => (this.currentPriority = null);
    this.currentPriority = priority;
    speechSynthesis.speak(u);
  }

  setMuted(m: boolean): void {
    this.muted = m;
    if (m && typeof speechSynthesis !== "undefined") speechSynthesis.cancel();
  }
}
