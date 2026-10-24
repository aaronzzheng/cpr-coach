// Hands-free voice commands in the browser (Web Speech API): "swap", "how long", "how am I doing",
// "stop", and "done" after rescue breaths. Same keyword tables as the phone (VoiceCommands.swift);
// negatives win ("don't stop" never stops) and the coach's own voice is ignored.
import type { Lang } from "../i18n";

export type VoiceCommand = "stop" | "swap" | "time" | "status" | "done";

interface Words {
  stop: string[];
  dontStop: string[];
  swap: string[];
  time: string[];
  status: string[];
  done: string[];
}

const TABLE: Record<Lang, Words> = {
  en: {
    stop: ["stop", "end session", "finish"], dontStop: ["don't stop", "dont stop", "do not stop"],
    swap: ["swap", "switch", "take over", "change rescuer"], time: ["how long", "what time", "timer"],
    status: ["how am i doing", "how's it going", "how is it going", "how do i look", "status", "feedback"],
    done: ["done", "finished", "breaths done", "resume"],
  },
  es: {
    stop: ["detente", "parar", "alto", "stop", "termina"], dontStop: ["no pares", "no parar", "sin parar"],
    swap: ["cambio", "cambiar", "relevo", "relévame"], time: ["cuánto tiempo", "cuanto tiempo", "tiempo"],
    status: ["cómo voy", "como voy", "cómo lo hago", "como lo hago", "qué tal", "que tal"], done: ["listo", "hecho", "ya está"],
  },
  fr: {
    stop: ["stop", "arrête", "arrêter", "arrete", "termine"], dontStop: ["n'arrête pas", "arrête pas", "sans arrêt"],
    swap: ["change", "changer", "relais", "relève", "remplace"], time: ["combien de temps", "temps"],
    status: ["comment je fais", "comment ça va", "comment ca va", "je fais bien"], done: ["fini", "terminé", "c'est fait"],
  },
  zh: {
    stop: ["停止", "停下", "停", "结束"], dontStop: ["不要停", "别停", "不停"], swap: ["换人", "交换", "换一下", "替换"],
    time: ["多久", "多长时间", "几分钟", "时间"], status: ["怎么样", "做得对", "做得好吗"], done: ["好了", "完成"],
  },
  ko: {
    stop: ["멈춰", "그만", "정지", "스톱", "종료"], dontStop: ["멈추지 마", "멈추지마", "계속"], swap: ["교대", "바꿔", "교체"],
    time: ["얼마나", "몇 분", "시간"], status: ["어때", "잘하고", "괜찮아"], done: ["다 했어", "완료", "끝났어"],
  },
  ja: {
    stop: ["止めて", "やめて", "ストップ", "停止", "とめて", "終了"], dontStop: ["止めないで", "やめないで"],
    swap: ["交代", "代わって", "かわって"], time: ["どのくらい", "何分", "時間"], status: ["どう", "調子", "大丈夫"],
    done: ["できた", "終わった", "完了"],
  },
  hi: {
    stop: ["रुको", "रोको", "बंद करो", "स्टॉप", "stop"], dontStop: ["मत रुको", "रुकना मत"], swap: ["बदलो", "बदल", "स्वैप", "swap"],
    time: ["कितना समय", "कितनी देर", "समय"], status: ["कैसा कर", "कैसे कर", "ठीक है क्या"], done: ["हो गया", "हो गई"],
  },
};

/** `expectingDone`: rescue breaths are underway, so "done" means resume. */
export function matchCommand(text: string, lang: Lang, expectingDone = false): VoiceCommand | null {
  const w = TABLE[lang];
  const t = ` ${text.toLowerCase().replace(/’/g, "'")} `;
  const tokens = new Set(t.split(/[^\p{L}\p{N}']+/u).filter(Boolean));
  // Languages without spaces (and Korean/Hindi endings) match substrings; elsewhere whole words.
  const substrings = lang === "zh" || lang === "ja" || lang === "ko" || lang === "hi";
  const has = (ps: string[]) => ps.some((p) => (substrings || p.includes(" ") || p.includes("'") ? t.includes(p) : tokens.has(p)));
  if (expectingDone && has(w.done)) return "done";
  if (has(w.swap)) return "swap";
  if (has(w.status)) return "status";
  if (has(w.time)) return "time";
  if (has(w.stop) && !has(w.dontStop)) return "stop";
  return null;
}

interface Recognition {
  lang: string;
  continuous: boolean;
  interimResults: boolean;
  start(): void;
  stop(): void;
  abort(): void;
  onresult: ((e: { resultIndex: number; results: ArrayLike<ArrayLike<{ transcript: string }> & { isFinal: boolean }> }) => void) | null;
  onend: (() => void) | null;
  onerror: ((e: { error: string }) => void) | null;
}

type RecognitionCtor = new () => Recognition;

/** Continuous recognition that reports each new phrase once; restarts itself when the browser stops it. */
export class VoiceListener {
  private rec: Recognition | null = null;
  private want = false;
  private consumed = new Map<number, number>();
  listening = false;
  error: string | null = null;

  constructor(
    private readonly onPhrase: (text: string) => boolean,
    private readonly isEchoWindow: () => boolean,
  ) {}

  static get supported(): boolean {
    const w = window as unknown as { SpeechRecognition?: RecognitionCtor; webkitSpeechRecognition?: RecognitionCtor };
    return Boolean(w.SpeechRecognition ?? w.webkitSpeechRecognition);
  }

  start(bcp47: string): void {
    this.stop();
    const w = window as unknown as { SpeechRecognition?: RecognitionCtor; webkitSpeechRecognition?: RecognitionCtor };
    const Ctor = w.SpeechRecognition ?? w.webkitSpeechRecognition;
    if (!Ctor) {
      this.error = "Voice commands need Chrome or Safari.";
      return;
    }
    const rec = new Ctor();
    rec.lang = bcp47;
    rec.continuous = true;
    rec.interimResults = true;
    rec.onresult = (e) => {
      for (let i = e.resultIndex; i < e.results.length; i++) {
        const text = e.results[i][0].transcript;
        const done = this.consumed.get(i) ?? 0;
        if (text.length <= done) continue;
        if (this.isEchoWindow()) {
          this.consumed.set(i, text.length); // the coach talking; skip it
          continue;
        }
        if (this.onPhrase(text.slice(done))) this.consumed.set(i, text.length);
      }
    };
    rec.onerror = (e) => {
      if (e.error === "not-allowed" || e.error === "service-not-allowed") {
        this.error = "Microphone access is off for this page.";
        this.want = false;
      }
    };
    rec.onend = () => {
      this.consumed.clear();
      this.listening = false;
      if (this.want) {
        try {
          rec.start();
          this.listening = true;
        } catch {
          // already restarting
        }
      }
    };
    this.rec = rec;
    this.want = true;
    this.error = null;
    try {
      rec.start();
      this.listening = true;
    } catch (err) {
      this.error = err instanceof Error ? err.message : String(err);
    }
  }

  stop(): void {
    this.want = false;
    this.rec?.abort();
    this.rec = null;
    this.listening = false;
    this.consumed.clear();
  }
}
