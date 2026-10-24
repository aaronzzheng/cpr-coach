// Report for paramedics: the session's timeline and CPR quality, as a list, a QR code and text
// to share. Mirrors the phone's HandoffSheet.
import { ClipboardList, Copy, X } from "lucide-react";
import QRCode from "qrcode";
import { useEffect, useState } from "react";
import type { Summary } from "../net/api";
import { t } from "../i18n";
import { formatClock } from "./Timer";

export interface TimelineEvent {
  at: Date;
  label: string;
}

const clock = (d: Date) => d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", second: "2-digit" });

export function handoffText(events: TimelineEvent[], s: Summary, swaps: number): string {
  const lines = [t("CPR Coach handoff"), "", ...events.map((e) => `${clock(e.at)}  ${e.label}`), ""];
  const el = s.elapsed_s ?? 0;
  lines.push(t("CPR time: %@ min %@ s", Math.floor(el / 60), Math.round(el % 60)));
  lines.push(t("Compressions: %@", s.compressions));
  if (s.avg_rate_cpm !== null) lines.push(t("Average rate: %@ /min", Math.round(s.avg_rate_cpm)));
  if (s.avg_depth_cm !== null) lines.push(t("Average depth: %@ cm", s.avg_depth_cm.toFixed(1)));
  if (s.ccf !== null) lines.push(t("Hands-on time: %@", `${Math.round(s.ccf * 100)}%`));
  lines.push(t("Pauses over 2 s: %@ (longest %@ s)", s.pauses, Math.round(s.longest_pause_s)));
  lines.push(t("Rescuer switches: %@", swaps));
  return lines.join("\n");
}

export function HandoffSheet({ events, summary: s, swaps, onClose }: { events: TimelineEvent[]; summary: Summary; swaps: number; onClose: () => void }) {
  const text = handoffText(events, s, swaps);
  const [qr, setQr] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);
  useEffect(() => {
    QRCode.toDataURL(text, { margin: 1, width: 240, errorCorrectionLevel: "M" }).then(setQr, () => setQr(null));
  }, [text]);

  return (
    <div className="overlay" role="dialog" aria-modal="true" aria-label={t("For paramedics")}>
      <div className="sheet handoff">
        <header className="sheet-head">
          <div>
            <p className="eyebrow-name">
              <ClipboardList size={18} aria-hidden="true" /> {t("For paramedics")}
            </p>
            <p className="lede">{t("Paramedics can scan this, or you can send it.")}</p>
          </div>
          <button className="icon-btn" onClick={onClose} aria-label={t("Close")}>
            <X size={20} aria-hidden="true" />
          </button>
        </header>
        <div className="handoff-body">
          <ol className="timeline">
            {events.map((e, i) => (
              <li key={i}>
                <span className="timeline-time">{clock(e.at)}</span>
                <span>{e.label}</span>
              </li>
            ))}
          </ol>
          {qr && <img className="qr" src={qr} alt={t("QR code of this report")} width={200} height={200} />}
        </div>
        <div className="stats">
          <div className="stat"><span className="stat-label">{t("CPR time")}</span><span className="stat-value">{formatClock(s.elapsed_s ?? 0)}</span></div>
          <div className="stat"><span className="stat-label">{t("Compressions")}</span><span className="stat-value">{s.compressions}</span></div>
          <div className="stat"><span className="stat-label">{t("Average rate")}</span><span className="stat-value">{s.avg_rate_cpm === null ? "—" : `${Math.round(s.avg_rate_cpm)} ${t("/min")}`}</span></div>
          <div className="stat"><span className="stat-label">{t("Average depth")}</span><span className="stat-value">{s.avg_depth_cm === null ? "—" : `${s.avg_depth_cm.toFixed(1)} cm`}</span></div>
          <div className="stat"><span className="stat-label">{t("Hands on chest")}</span><span className="stat-value">{s.ccf === null ? "—" : `${Math.round(s.ccf * 100)}%`}</span></div>
          <div className="stat"><span className="stat-label">{t("Rescuer switches")}</span><span className="stat-value">{swaps}</span></div>
        </div>
        <div className="actions end">
          <button
            className="btn secondary lg"
            onClick={() => void navigator.clipboard.writeText(text).then(() => setCopied(true), () => setCopied(false))}
          >
            <Copy size={18} aria-hidden="true" />
            {copied ? t("Copied") : t("Copy report")}
          </button>
          <button className="btn primary lg" onClick={onClose}>
            {t("Done")}
          </button>
        </div>
      </div>
    </div>
  );
}
