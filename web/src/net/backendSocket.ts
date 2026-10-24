// Reconnecting WebSocket to the backend's /ws: keeps the latest state, recent compression
// events, and converts them into a WatchSnapshot for fusion.
import { BACKEND } from "../config";
import type { WatchSnapshot } from "../fusion/fuse";
import type { ClientCmd, CompressionMsg, ServerMsg, StateMsg } from "./messages";

export class BackendSocket {
  state: StateMsg | null = null;
  /** performance.now()/1000 when `state` arrived. */
  stateAt = 0;
  events: CompressionMsg[] = [];
  connected = false;

  private ws: WebSocket | null = null;
  private retry = 0;
  private closed = false;
  private timer: ReturnType<typeof setTimeout> | null = null;

  connect(): void {
    this.closed = false;
    const url = `${location.protocol === "https:" ? "wss" : "ws"}://${location.host}/ws`;
    const ws = new WebSocket(url);
    this.ws = ws;
    // Handlers ignore sockets that have been replaced, so a late close from an old socket
    // can't spawn a second live connection (which would deliver every event twice).
    ws.onopen = () => {
      if (this.ws !== ws) return;
      this.connected = true;
      this.retry = 0;
    };
    ws.onmessage = (e) => {
      if (this.ws === ws) this.onMessage(JSON.parse(e.data as string) as ServerMsg);
    };
    ws.onclose = () => {
      if (this.ws !== ws) return;
      this.connected = false;
      this.ws = null;
      if (this.closed) return;
      const delay = BACKEND.reconnectDelaysMs[Math.min(this.retry++, BACKEND.reconnectDelaysMs.length - 1)];
      this.timer = setTimeout(() => this.connect(), delay);
    };
  }

  close(): void {
    this.closed = true;
    if (this.timer) clearTimeout(this.timer);
    const ws = this.ws;
    this.ws = null;
    this.connected = false;
    ws?.close();
  }

  send(cmd: ClientCmd): void {
    if (this.ws?.readyState === WebSocket.OPEN) this.ws.send(JSON.stringify(cmd));
  }

  private onMessage(msg: ServerMsg): void {
    if (msg.type === "state") {
      this.state = msg;
      this.stateAt = performance.now() / 1000;
    } else {
      this.events.push(msg);
      if (this.events.length > BACKEND.maxEvents) this.events.shift();
    }
  }

  /** Seconds since the latest state arrived, extrapolating the backend clock to "now". */
  backendNow(): number | null {
    return this.state ? this.state.ts + (performance.now() / 1000 - this.stateAt) : null;
  }

  watchSnapshot(): WatchSnapshot | null {
    const s = this.state;
    const now = this.backendNow();
    if (!s || now === null || !this.connected || !s.sources.watch_streaming) return null;
    if (now - s.ts > BACKEND.stateStaleS) return null;
    const c = s.compressions;
    return {
      rateCpm: c.rate_cpm,
      depthCm: c.depth_avg5_cm,
      lastCompressionAgeS: c.last_t === null ? null : now - c.last_t,
      count: c.count,
      hrBpm: s.hr.bpm !== null && s.hr.age_s !== null && s.hr.age_s < BACKEND.hrStaleS ? s.hr.bpm : null,
      swapRecommended: s.fatigue.swap_recommended,
      fatigueScore: s.fatigue.score,
    };
  }
}
