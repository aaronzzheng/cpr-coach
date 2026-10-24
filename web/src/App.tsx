// Live dashboard: owns the camera pipeline, the fusion/coach tick loop, metronome, speech,
// the idle → countdown → running flow, and the operator keyboard shortcuts.
import { useCallback, useEffect, useRef, useState } from "react";
import { Metronome } from "./audio/metronome";
import { CoachEngine } from "./coach/coachEngine";
import type { Rule } from "./coach/rules";
import { Speech } from "./coach/speech";
import { CameraView } from "./components/CameraView";
import { CoachBanner } from "./components/CoachBanner";
import { DepthBar } from "./components/DepthBar";
import { PostureChecklist } from "./components/PostureChecklist";
import { RateGauge } from "./components/RateGauge";
import { StatusPills, type PillState } from "./components/StatusPills";
import { Timer } from "./components/Timer";
import { Waveform, type WaveSample } from "./components/Waveform";
import { CAMERA_COMPRESSIONS, COACH, COUNTDOWN_S, UI_TICK_MS } from "./config";
import { cameraCmPerPx, fuse, type CameraSnapshot, type LiveState } from "./fusion/fuse";
import { useHealth } from "./net/health";
import { CameraPipeline, type CameraStatus } from "./pose/cameraPipeline";

type Phase = "idle" | "countdown" | "running";

interface View {
  now: number;
  live: LiveState;
  cam: CameraSnapshot;
  camStatus: CameraStatus;
  camError: string | null;
  poseFps: number;
  trace: WaveSample[];
  ticks: number[];
}

const nowS = () => performance.now() / 1000;

export default function App() {
  const health = useHealth();
  const videoRef = useRef<HTMLVideoElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const pipeline = useRef<CameraPipeline | null>(null);
  const engine = useRef(new CoachEngine());
  const speech = useRef<Speech | null>(null);
  const metronome = useRef(new Metronome());

  const [view, setView] = useState<View | null>(null);
  const [phase, setPhase] = useState<Phase>("idle");
  const [countdown, setCountdown] = useState(0);
  const [banner, setBanner] = useState<Rule | null>(null);
  const [muted, setMuted] = useState(false);
  const [metronomeOn, setMetronomeOn] = useState(true);
  const [debug, setDebug] = useState(false);

  const phaseRef = useRef<Phase>("idle");
  const runStart = useRef(0);
  const lastCoach = useRef(0);
  const countdownTimer = useRef<ReturnType<typeof setInterval> | null>(null);
  phaseRef.current = phase;

  // Camera pipeline lives for the whole page; started automatically.
  useEffect(() => {
    speech.current ??= new Speech();
    if (!videoRef.current || !canvasRef.current) return;
    const p = new CameraPipeline(videoRef.current, canvasRef.current);
    pipeline.current = p;
    void p.start();
    return () => p.stop();
  }, []);

  // UI tick: fuse sources, refresh the view, and run the coach every COACH.evalIntervalMs.
  useEffect(() => {
    const id = setInterval(() => {
      const p = pipeline.current;
      if (!p) return;
      const now = nowS();
      const cam = p.snapshot();
      const live = fuse(null, cam);
      setView({
        now,
        live,
        cam,
        camStatus: p.status,
        camError: p.error,
        poseFps: p.poseFps,
        trace: p.detector.trace.map((s) => ({ t: s.t, v: s.y })),
        ticks: [...p.detector.ticks],
      });

      if (phaseRef.current === "running" && now - lastCoach.current >= COACH.evalIntervalMs / 1000) {
        lastCoach.current = now;
        const d = engine.current.evaluate(live, now - runStart.current, now);
        setBanner(d.banner);
        if (d.speak) speech.current?.say(d.speak.line, d.speak.priority);
      }
    }, UI_TICK_MS);
    return () => clearInterval(id);
  }, []);

  const stop = useCallback(() => {
    if (countdownTimer.current) clearInterval(countdownTimer.current);
    metronome.current.stop();
    setPhase("idle");
    setBanner(null);
  }, []);

  const start = useCallback(() => {
    // Runs inside a user gesture, which unlocks audio and speech for the rest of the session.
    metronome.current.prime();
    speech.current?.say("Get ready.", 0);
    setPhase("countdown");
    setCountdown(COUNTDOWN_S);
    let left = COUNTDOWN_S;
    countdownTimer.current = setInterval(() => {
      left -= 1;
      setCountdown(left);
      if (left > 0) return;
      if (countdownTimer.current) clearInterval(countdownTimer.current);
      runStart.current = nowS();
      engine.current.reset();
      pipeline.current?.resetSession();
      if (metronomeOn) metronome.current.start();
      speech.current?.say("Start compressions.", 0);
      setPhase("running");
    }, 1000);
  }, [metronomeOn]);

  const toggleMetronome = useCallback(() => {
    setMetronomeOn((on) => {
      if (on) metronome.current.stop();
      else if (phaseRef.current === "running") metronome.current.start();
      return !on;
    });
  }, []);

  const toggleMute = useCallback(() => {
    setMuted((m) => {
      speech.current?.setMuted(!m);
      return !m;
    });
  }, []);

  const toggleCamera = useCallback(() => {
    const p = pipeline.current;
    if (!p) return;
    if (p.status === "on" || p.status === "starting") p.stop();
    else void p.start();
  }, []);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.target instanceof HTMLInputElement || e.metaKey || e.ctrlKey) return;
      switch (e.key.toLowerCase()) {
        case " ":
          e.preventDefault();
          if (phaseRef.current === "idle") start();
          else stop();
          break;
        case "m":
          toggleMute();
          break;
        case "b":
          toggleMetronome();
          break;
        case "c":
          toggleCamera();
          break;
        case "d":
          setDebug((d) => !d);
          break;
        case "f":
          if (document.fullscreenElement) void document.exitFullscreen();
          else void document.documentElement.requestFullscreen();
          break;
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [start, stop, toggleMute, toggleMetronome, toggleCamera]);

  const camPill: PillState =
    view?.camStatus === "on" ? (view.cam.posture?.visible ? "on" : "warn") : view?.camStatus === "starting" ? "warn" : "off";
  const live = view?.live;
  const elapsed = phase === "running" && view ? view.now - runStart.current : 0;

  return (
    <div className="app">
      <header className="topbar">
        <h1>CPR COACH</h1>
        <StatusPills
          pills={[
            { label: "Backend", state: health.backend ? "on" : "off" },
            { label: "Watch", state: health.watch_streaming ? "on" : "off" },
            { label: "Phone", state: health.phone_connected ? "on" : "off" },
            { label: "Camera", state: camPill },
          ]}
        />
        <div className="toggles">
          <span className={metronomeOn ? "on" : ""}>♪ Metronome [B]</span>
          <span className={muted ? "" : "on"}>🔊 Voice [M]</span>
        </div>
        <Timer seconds={elapsed} />
      </header>

      <section className="top">
        <div className="camera-wrap">
          <CameraView ref={videoRef} canvasRef={canvasRef} status={view?.camStatus ?? "off"} error={view?.camError ?? null} />
          {phase === "countdown" && <div className="countdown">{countdown > 0 ? countdown : "GO"}</div>}
        </div>
        <div className="metrics">
          <RateGauge cpm={live?.rate.cpm ?? null} source={live?.rate.source ?? null} />
          <DepthBar cm={live?.depth.cm ?? null} estimate={live?.depth.estimate ?? false} source={live?.depth.source ?? null} />
        </div>
      </section>

      <section className="wave-row">
        <Waveform samples={view?.trace ?? []} ticks={view?.ticks ?? []} now={view?.now ?? 0} spanS={CAMERA_COMPRESSIONS.traceS} />
        <span className="wave-label">wrist motion · {live?.compressionCount ?? 0} compressions</span>
      </section>

      {live && <PostureChecklist live={live} />}

      <CoachBanner
        rule={phase === "running" ? banner : null}
        idleText={phase === "countdown" ? "Get ready…" : phase === "running" ? "Keep going" : "Press SPACE to start"}
      />

      <footer className="footer">
        Training tool – not a medical device · Space start/stop · B metronome · M mute · C camera · D debug · F fullscreen
      </footer>

      {debug && view && (
        <pre className="debug">
          {[
            `pose fps      ${view.poseFps}`,
            `side          ${view.cam.posture?.side ?? "—"}  visible=${view.cam.posture?.visible ?? false}`,
            `elbow         ${view.cam.posture?.elbowAngleDeg?.toFixed(0) ?? "—"}°  frac=${view.cam.posture?.elbowViolationFrac.toFixed(2) ?? "—"}`,
            `align         ${view.cam.posture?.alignAngleDeg?.toFixed(0) ?? "—"}°  frac=${view.cam.posture?.alignViolationFrac.toFixed(2) ?? "—"}`,
            `cam count     ${view.cam.compressions.count}`,
            `cam rate      ${view.cam.compressions.rateCpm?.toFixed(1) ?? "—"}`,
            `cam amp px    ${view.cam.compressions.amplitudePx?.toFixed(1) ?? "—"}`,
            `cm/px         ${cameraCmPerPx(view.cam)?.toFixed(3) ?? "—"} (${view.cam.calibratedCmPerPx ? "calibrated" : "arm-length guess"})`,
            `recoil (beta) ${view.cam.compressions.incompleteRecoil ? "INCOMPLETE" : "ok"}`,
            `last comp     ${view.cam.lastCompressionAgeS?.toFixed(1) ?? "—"} s ago`,
          ].join("\n")}
        </pre>
      )}
    </div>
  );
}
