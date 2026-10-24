// Top-10 list: rank, name, grade, score.
import type { LeaderboardEntry } from "../net/api";

export function Leaderboard({ entries, highlight }: { entries: LeaderboardEntry[]; highlight?: string }) {
  if (!entries.length) return <p className="empty">No scores yet. Finish a session and save it here.</p>;
  return (
    <ol className="board">
      {entries.map((e, i) => (
        <li key={e.session_id} className={e.session_id === highlight ? "me" : ""}>
          <span className="board-rank">{i + 1}</span>
          <span className="board-name">{e.name}</span>
          <span className={`grade-pill g${e.grade}`}>{e.grade}</span>
          <span className="board-score">{Math.round(e.score)}</span>
        </li>
      ))}
    </ol>
  );
}
