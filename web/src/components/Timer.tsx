// mm:ss session clock.
export function formatClock(s: number): string {
  const total = Math.max(0, Math.floor(s));
  return `${String(Math.floor(total / 60)).padStart(2, "0")}:${String(total % 60).padStart(2, "0")}`;
}

export function Timer({ seconds, label }: { seconds: number; label?: string }) {
  return (
    <div className="timer">
      {label && <span className="timer-label">{label}</span>}⏱ {formatClock(seconds)}
    </div>
  );
}
