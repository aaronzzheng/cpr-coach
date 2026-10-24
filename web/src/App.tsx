import { StatusPills } from "./components/StatusPills";
import { useHealth } from "./net/health";

export default function App() {
  const health = useHealth();

  return (
    <div className="app">
      <header className="topbar">
        <h1>CPR COACH</h1>
        <StatusPills
          pills={[
            { label: "Backend", on: health.backend },
            { label: "Watch", on: health.watch_streaming },
            { label: "Phone", on: health.phone_connected },
            { label: "Camera", on: false },
          ]}
        />
        <div className="timer">⏱ 00:00</div>
      </header>
      <main className="placeholder">Dashboard coming in M1</main>
      <footer className="footer">Training tool – not a medical device</footer>
    </div>
  );
}
