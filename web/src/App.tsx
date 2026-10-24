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
import { BackendSocket } from "./net/backendSocket";
import type { StateMsg } from "./net/messages";
import { CameraPipeline, type CameraStatus } from "./pose/cameraPipeline";

type Phase = "idle" | "countdown" | "running";

interface View {
  now: number;
  live: LiveState;
  cam: CameraSnapshot;
  camStatus: CameraStatus;
  camError: string | null;
  poseFps: number;
  backend: StateMsg | null;
  backendUp: boolean;
  wave: { samples: WaveSample[]; ticks: number[]; now: number; label: string };
}

const nowS = () => performance.now() / 1000;

export default function App() {
  const videoRef = useRef<HTMLVideoElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const pipeline = useRef<CameraPipeline | null>(null);
  const engine = useRef(new CoachEngine());
  const speech = useRef<Speech | null>(null);
  const metronome = useRef(new Metronome());
  const backend = useRef(new BackendSocket());

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
    const b = backend.current;
    b.connect();
    return () => {
      p.stop();
      b.close();
    };
  }, []);

  // UI tick: fuse sources, refresh the view, and run the coach every COACH.evalIntervalMs.
  useEffect(() => {
    const id = setInterval(() => {
      const p = pipeline.current;
      if (!p) return;
      const now = nowS();
      const cam = p.snapshot();
      const b = backend.current;
      const live = fuse(b.watchSnapshot(), cam);
      setView({
        now,
        live,
        cam,
        camStatus: p.status,
        camError: p.error,
        poseFps: p.poseFps,
        backend: b.state,
        backendUp: b.connected,
        wave: waveFor(live, b, p),
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
    if (phaseRef.current === "running") backend.current.send({ cmd: "stop" });
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
      backend.current.send({ cmd: "start", name: "" });
      if (metronomeOn) metronome.current.start();
      speech.current?.say("Start compressions.", 0);
      setPhase("running");
    }, 1000);
  }, [metronomeOn]);

  const toggleMetronome = useCallback(() => {
    setMetronomeOn((on) => {
      if (on) metronome.current.stop();
      else if (phaseRef.current === "running") metronome.current.start();
      backend.current.send({ cmd: "metronome", on: !on, bpm: metronome.current.bpm });
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
        case "s":
          backend.current.send({ cmd: "swap" });
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
  const bs = view?.backend;
  const watchLabel = bs?.sources.source === "sim" ? "Watch (sim)" : bs?.sources.source === "replay" ? "Watch (replay)" : "Watch";

  return (
    <div className="app">
      <header className="topbar">
        <h1>CPR COACH</h1>
        <StatusPills
          pills={[
            { label: "Backend", state: view?.backendUp ? "on" : "off" },
            { label: watchLabel, state: bs?.sources.watch_streaming ? "on" : "off" },
            { label: "Phone", state: bs?.sources.phone_connected ? "on" : "off" },
            { label: "Camera", state: camPill },
          ]}
        />
        <div className="toggles">
          <span className={metronomeOn ? "on" : ""}>♪ Metronome [B]</span>
          <span className={muted ? "" : "on"}>🔊 Voice [M]</span>
        </div>
        {live?.rate.source === "watch" && bs && <Timer seconds={bs.session.cycle_elapsed_s} label="cycle" />}
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
        <Waveform
          samples={view?.wave.samples ?? []}
          ticks={view?.wave.ticks ?? []}
          now={view?.wave.now ?? 0}
          spanS={CAMERA_COMPRESSIONS.traceS}
        />
        <span className="wave-label">
          {view?.wave.label ?? ""} · {live?.compressionCount ?? 0} compressions
        </span>
      </section>

      {live && <PostureChecklist live={live} />}

      <CoachBanner
        rule={phase === "running" ? banner : null}
        idleText={phase === "countdown" ? "Get ready…" : phase === "running" ? "Keep going" : "Press SPACE to start"}
      />

      <footer className="footer">
        Training tool – not a medical device · Space start/stop · B metronome · S swap · M mute · C camera · D debug · F fullscreen
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
            ``,
            `backend ws    ${view.backendUp ? "up" : "down"}  source=${bs?.sources.source ?? "—"}`,
            `packets       ${bs?.sources.packet_rate_hz.toFixed(1) ?? "—"}/s  gaps=${bs?.sources.gaps ?? "—"}  age=${bs?.sources.last_packet_age_ms ?? "—"} ms`,
            `watch rate    ${bs?.compressions.rate_cpm?.toFixed(1) ?? "—"}  depth5=${bs?.compressions.depth_avg5_cm?.toFixed(2) ?? "—"}`,
            `pauses        ${bs?.pauses.count ?? 0}  hands-off=${bs?.pauses.hands_off_s.toFixed(1) ?? "—"} s  ccf=${bs?.pauses.ccf?.toFixed(2) ?? "—"}`,
            `fatigue       ${bs?.fatigue.score.toFixed(2) ?? "—"}  base=${bs?.fatigue.baseline_depth_cm?.toFixed(2) ?? "—"}  recent=${bs?.fatigue.recent_depth_cm?.toFixed(2) ?? "—"}`,
          ].join("\n")}
        </pre>
      )}
    </div>
  );
}

/** Watch a_up when the watch is the active source, otherwise the camera wrist trace. */
function waveFor(live: LiveState, b: BackendSocket, p: CameraPipeline): View["wave"] {
  const s = b.state;
  const now = b.backendNow();
  if (live.rate.source === "watch" && s && now !== null) {
    const { t0, fs, a_up } = s.wave;
    return {
      samples: a_up.map((v, i) => ({ t: t0 + i / fs, v })),
      ticks: b.events.map((e) => e.t),
      now,
      label: "watch vertical accel",
    };
  }
  return {
    samples: p.detector.trace.map((x) => ({ t: x.t, v: x.y })),
    ticks: [...p.detector.ticks],
    now: nowS(),
    label: "wrist motion",
  };
}
