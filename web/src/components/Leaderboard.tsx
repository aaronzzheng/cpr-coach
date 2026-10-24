// Top-10 judge leaderboard.
import type { LeaderboardEntry } from "../net/api";

export function Leaderboard({ entries, highlight }: { entries: LeaderboardEntry[]; highlight?: string }) {
  if (!entries.length) return <div className="board-empty">No scores yet — be the first.</div>;
  return (
    <ol className="board">
      {entries.map((e, i) => (
        <li key={e.session_id} className={e.session_id === highlight ? "me" : ""}>
          <span className="board-rank">{i + 1}</span>
          <span className="board-name">{e.name}</span>
          <span className="board-score">
            {Math.round(e.score)} <small>{e.grade}</small>
          </span>
          <span className="board-date">{new Date(e.date).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })}</span>
        </li>
      ))}
    </ol>
  );
}
