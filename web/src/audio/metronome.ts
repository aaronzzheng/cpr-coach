// Audio metronome using WebAudio look-ahead scheduling ("A Tale of Two Clocks"):
// a coarse JS timer schedules sample-accurate oscillator clicks slightly ahead of time.
import { METRONOME, TARGETS } from "../config";

export class Metronome {
  bpm: number = TARGETS.rate_target_cpm;
  private ctx: AudioContext | null = null;
  private timer: ReturnType<typeof setInterval> | null = null;
  private nextNoteTime = 0;
  private beat = 0;

  get running(): boolean {
    return this.timer !== null;
  }

  /** Call from a user gesture (browser autoplay policy) before a delayed start(). */
  prime(): void {
    this.ctx ??= new AudioContext();
    void this.ctx.resume();
  }

  start(): void {
    if (this.timer) return;
    this.prime();
    if (!this.ctx) return;
    this.nextNoteTime = this.ctx.currentTime + 0.05;
    this.beat = 0;
    this.timer = setInterval(() => this.schedule(), METRONOME.tickMs);
  }

  stop(): void {
    if (this.timer) clearInterval(this.timer);
    this.timer = null;
  }

  private schedule(): void {
    const ctx = this.ctx;
    if (!ctx) return;
    while (this.nextNoteTime < ctx.currentTime + METRONOME.lookaheadS) {
      this.click(ctx, this.nextNoteTime, this.beat % METRONOME.accentEvery === 0);
      this.nextNoteTime += 60 / this.bpm;
      this.beat++;
    }
  }

  private click(ctx: AudioContext, at: number, accent: boolean): void {
    const osc = ctx.createOscillator();
    const gain = ctx.createGain();
    osc.frequency.value = accent ? METRONOME.accentFreqHz : METRONOME.freqHz;
    gain.gain.setValueAtTime(accent ? 0.6 : 0.35, at);
    gain.gain.exponentialRampToValueAtTime(0.001, at + METRONOME.clickS);
    osc.connect(gain).connect(ctx.destination);
    osc.start(at);
    osc.stop(at + METRONOME.clickS);
  }
}
