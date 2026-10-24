// Polls /api/health so the header can show which sources are alive.
import { useEffect, useState } from "react";
import { HEALTH_POLL_MS } from "../config";

export interface Health {
  backend: boolean;
  phone_connected: boolean;
  watch_streaming: boolean;
}

const OFFLINE: Health = { backend: false, phone_connected: false, watch_streaming: false };

export function useHealth(): Health {
  const [health, setHealth] = useState<Health>(OFFLINE);

  useEffect(() => {
    let alive = true;
    const poll = async () => {
      try {
        const r = await fetch("/api/health");
        const j = (await r.json()) as { ok: boolean; sources: Omit<Health, "backend"> };
        if (alive) setHealth({ backend: j.ok, ...j.sources });
      } catch {
        if (alive) setHealth(OFFLINE);
      }
    };
    void poll();
    const id = setInterval(poll, HEALTH_POLL_MS);
    return () => {
      alive = false;
      clearInterval(id);
    };
  }, []);

  return health;
}
