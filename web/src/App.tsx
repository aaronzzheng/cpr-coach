// Dashboard shell: owns the camera pipeline, backend socket, fusion/coach tick loop, metronome
// and speech, and the home → calibrate / countdown → running → summary flow (PRD §8.1).
import { useCallback, useEffect, useRef, useState } from "react";
import { Metronome } from "./audio/metronome";
import { computeCalibration, type CalibrationResult } from "./calibration/calibrate";
import { CoachEngine } from "./coach/coachEngine";
import type { Rule } from "./coach/rules";
import { Speech } from "./coach/speech";
import { CalibrationWizard, type CalibrationStep } from "./components/CalibrationWizard";
import { CameraView } from "./components/CameraView";
import { CoachBanner } from "./components/CoachBanner";
import { DepthBar } from "./components/DepthBar";
import { HomePanel } from "./components/HomePanel";
import { PostureChecklist } from "./components/PostureChecklist";
import { RateGauge } from "./components/RateGauge";
import { StatusPills, type PillState } from "./components/StatusPills";
import { SummaryCard } from "./components/SummaryCard";
import { Timer } from "./components/Timer";
import { Waveform, type WaveSample } from "./components/Waveform";
import { CALIBRATION, CAMERA_COMPRESSIONS, COACH, COUNTDOWN_S, UI_TICK_MS } from "./config";
import { cameraCmPerPx, fuse, type CameraSnapshot, type LiveState } from "./fusion/fuse";
import { api, type Calibration, type LeaderboardEntry, type Summary } from "./net/api";
import { BackendSocket } from "./net/backendSocket";
import type { CompressionMsg, StateMsg } from "./net/messages";
import { CameraPipeline, type CameraStatus } from "./pose/cameraPipeline";
import { SessionTracker } from "./session/sessionTracker";

type Phase = "home" | "calibrate" | "countdown" | "running" | "summary";

interface View {
  now: number;
  live: LiveState;
  cam: CameraSnapshot;
  camStatus: CameraStatus;
  camError: string | null;
  poseFps: number;
  backend: StateMsg | null;
  backendUp: boolean;
  elapsed: number;
  wave: { samples: WaveSample[]; ticks: number[]; now: number; label: string };
}

interface CalState {
  step: CalibrationStep;
  using: { watch: boolean; camera: boolean };
  counts: { watch: number; camera: number };
  result: CalibrationResult | null;
  saving: boolean;
  error: string | null;
}

const CAL_INITIAL: CalState = {
  step: "framing",
  using: { watch: false, camera: false },
  counts: { watch: 0, camera: 0 },
  result: null,
  saving: false,
  error: null,
};

const nowS = () => performance.now() / 1000;

export default function App() {
  const videoRef = useRef<HTMLVideoElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const pipeline = useRef<CameraPipeline | null>(null);
  const engine = useRef(new CoachEngine());
  const speech = useRef<Speech | null>(null);
  const metronome = useRef(new Metronome());
  const backend = useRef(new BackendSocket());
  const tracker = useRef<SessionTracker | null>(null);

  const [view, setView] = useState<View | null>(null);
  const [phase, setPhase] = useState<Phase>("home");
  const [countdown, setCountdown] = useState(0);
  const [banner, setBanner] = useState<Rule | null>(null);
  const [muted, setMuted] = useState(false);
  const [metronomeOn, setMetronomeOn] = useState(true);
  const [debug, setDebug] = useState(false);
  const [useWatch, setUseWatch] = useState(true);
  const [name, setName] = useState("");
  const [board, setBoard] = useState<LeaderboardEntry[]>([]);
  const [calibration, setCalibration] = useState<Calibration | null>(null);
  const [cal, setCal] = useState<CalState>(CAL_INITIAL);
  const [summary, setSummary] = useState<Summary | null>(null);
  const [summaryError, setSummaryError] = useState<string | null>(null);
  const [added, setAdded] = useState(false);
  const [homeError, setHomeError] = useState<string | null>(null);

  const phaseRef = useRef<Phase>("home");
  const useWatchRef = useRef(true);
  /** True if the watch was switched off at any point this session (summary then uses the camera). */
  const watchOverridden = useRef(false);
  const calRef = useRef<CalState>(CAL_INITIAL);
  const runStart = useRef(0);
  const lastCoach = useRef(0);
  const lastWatchEventT = useRef(0);
  const sessionId = useRef<string | null>(null);
  const calSamples = useRef<{ watch: number[]; camera: number[]; scale: number }>({ watch: [], camera: [], scale: 1 });
  const countdownTimer = useRef<ReturnType<typeof setInterval> | null>(null);
  phaseRef.current = phase;
  calRef.current = cal;
  useWatchRef.current = useWatch;

  const refreshBoard = useCallback(() => {
    api.leaderboard().then(setBoard, () => setBoard([]));
  }, []);

  const refreshCalibration = useCallback(() => {
    api.calibration().then(
      (c) => {
        setCalibration(c);
        if (pipeline.current) pipeline.current.calibratedCmPerPx = c.cm_per_px;
      },
      () => setCalibration(null),
    );
  }, []);

  // Camera pipeline and backend socket live for the whole page.
  useEffect(() => {
    speech.current ??= new Speech();
    if (!videoRef.current || !canvasRef.current) return;
    const p = new CameraPipeline(videoRef.current, canvasRef.current);
    pipeline.current = p;
    void p.start();
    const b = backend.current;
    b.connect();
    refreshBoard();
    refreshCalibration();
    return () => {
      p.stop();
      b.close();
    };
  }, [refreshBoard, refreshCalibration]);

  /** Watch compression events that arrived since the last call. */
  const newWatchEvents = (b: BackendSocket): CompressionMsg[] => {
    const fresh = b.events.filter((e) => e.t > lastWatchEventT.current);
    if (fresh.length) lastWatchEventT.current = fresh[fresh.length - 1].t;
    return fresh;
  };

  const finishCalibration = useCallback(() => {
    metronome.current.stop();
    const s = calSamples.current;
    const result = computeCalibration(s.watch, s.camera);
    setCal((c) => ({ ...c, step: "result", result }));
  }, []);

  // UI tick: fuse sources, feed the session tracker or calibration, run the coach.
  useEffect(() => {
    const id = setInterval(() => {
      const p = pipeline.current;
      if (!p) return;
      const now = nowS();
      const b = backend.current;
      const cam = p.snapshot();
      // W key: camera-only backup mode ignores the watch entirely.
      const live = fuse(useWatchRef.current ? b.watchSnapshot() : null, cam);
      const camEvents = p.drainCompressions();
      // Always drain, so turning the watch back on doesn't replay events from while it was off.
      const drained = newWatchEvents(b);
      const watchEvents = useWatchRef.current ? drained : [];
      const ph = phaseRef.current;

      if (ph === "running" && tracker.current) {
        const tr = tracker.current;
        const k = cameraCmPerPx(cam);
        for (const c of camEvents) tr.onCameraCompression(c.t, c.instRateCpm, c.amplitudePx !== null && k ? c.amplitudePx * k : null);
        const bNow = b.backendNow();
        if (bNow !== null) for (const e of watchEvents) tr.onCompression(now - (bNow - e.t));
        tr.onPosture(cam.posture);
      }

      const c = calRef.current;
      if (ph === "calibrate" && c.step === "compress") {
        const s = calSamples.current;
        if (c.using.watch) for (const e of watchEvents) if (e.depth_cm !== null) s.watch.push(e.depth_cm / s.scale);
        if (c.using.camera) for (const e of camEvents) if (e.amplitudePx !== null) s.camera.push(e.amplitudePx);
        const counts = { watch: s.watch.length, camera: s.camera.length };
        if (counts.watch !== c.counts.watch || counts.camera !== c.counts.camera) setCal((x) => ({ ...x, counts }));
        const n = CALIBRATION.compressions;
        if ((!c.using.watch || counts.watch >= n) && (!c.using.camera || counts.camera >= n)) finishCalibration();
      }

      setView({
        now,
        live,
        cam,
        camStatus: p.status,
        camError: p.error,
        poseFps: p.poseFps,
        backend: b.state,
        backendUp: b.connected,
        elapsed: ph === "running" && tracker.current ? tracker.current.elapsed(now) : 0,
        wave: waveFor(live, b, p),
      });

      if (ph === "running" && now - lastCoach.current >= COACH.evalIntervalMs / 1000) {
        lastCoach.current = now;
        const d = engine.current.evaluate(live, now - runStart.current, now);
        setBanner(d.banner);
        if (d.speak) speech.current?.say(d.speak.line, d.speak.priority);
      }
    }, UI_TICK_MS);
    return () => clearInterval(id);
  }, [finishCalibration]);

  const start = useCallback(() => {
    if (phaseRef.current !== "home") return;
    // Runs inside a user gesture, which unlocks audio and speech for the rest of the session.
    metronome.current.prime();
    speech.current?.say("Get ready.", 0);
    setHomeError(null);
    setPhase("countdown");
    setCountdown(COUNTDOWN_S);
    let left = COUNTDOWN_S;
    countdownTimer.current = setInterval(() => {
      left -= 1;
      setCountdown(left);
      if (left > 0) return;
      if (countdownTimer.current) clearInterval(countdownTimer.current);
      runStart.current = nowS();
      tracker.current = new SessionTracker(runStart.current);
      engine.current.reset();
      pipeline.current?.resetSession();
      sessionId.current = null;
      watchOverridden.current = !useWatchRef.current;
      api.startSession(name).then(
        (r) => (sessionId.current = r.session_id),
        (e: Error) => setHomeError(`Backend: ${e.message}`),
      );
      if (metronomeOn) metronome.current.start();
      speech.current?.say("Start compressions.", 0);
      setPhase("running");
    }, 1000);
  }, [metronomeOn, name]);

  const stop = useCallback(() => {
    if (countdownTimer.current) clearInterval(countdownTimer.current);
    metronome.current.stop();
    setBanner(null);
    if (phaseRef.current === "countdown") {
      setPhase("home");
      return;
    }
    if (phaseRef.current !== "running") return;
    const cam = tracker.current?.finish(nowS(), watchOverridden.current);
    setSummary(null);
    setSummaryError(null);
    setAdded(false);
    setPhase("summary");
    speech.current?.say("Stop. Well done.", 0);
    void (async () => {
      try {
        const { session_id } = await api.stopSession();
        if (!cam) throw new Error("no session data");
        setSummary(await api.postSummary(session_id, cam));
      } catch (e) {
        setSummaryError(e instanceof Error ? e.message : String(e));
      }
    })();
  }, []);

  const backHome = useCallback(() => {
    setPhase("home");
    setCal(CAL_INITIAL);
    refreshBoard();
  }, [refreshBoard]);

  const addToLeaderboard = useCallback(() => {
    if (!summary) return;
    api.addToLeaderboard(summary.session_id).then(
      (b) => {
        setBoard(b);
        setAdded(true);
      },
      (e: Error) => setSummaryError(e.message),
    );
  }, [summary]);

  // Calibration wizard actions.
  const beginCalibration = useCallback(() => {
    const using = {
      watch: backend.current.state?.sources.watch_streaming ?? false,
      camera: (view?.cam.on ?? false) && (view?.cam.posture?.visible ?? false),
    };
    calSamples.current = { watch: [], camera: [], scale: calibration?.depth_scale ?? 1 };
    metronome.current.start();
    setCal({ ...CAL_INITIAL, step: "compress", using });
  }, [view, calibration]);

  const saveCalibration = useCallback(() => {
    const r = cal.result;
    if (!r) return;
    setCal((c) => ({ ...c, saving: true, error: null }));
    api
      .saveCalibration({
        depth_scale: r.depthScaleOk && r.depthScale !== null ? r.depthScale : undefined,
        cm_per_px: r.cmPerPx ?? undefined,
      })
      .then(
        () => {
          refreshCalibration();
          backHome();
        },
        (e: Error) => setCal((c) => ({ ...c, saving: false, error: e.message })),
      );
  }, [cal.result, refreshCalibration, backHome]);

  const cancelCalibration = useCallback(() => {
    metronome.current.stop();
    backHome();
  }, [backHome]);

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

  const toggleWatch = useCallback(() => {
    setUseWatch((on) => {
      if (on && phaseRef.current === "running") watchOverridden.current = true;
      return !on;
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
          if (phaseRef.current === "home") start();
          else if (phaseRef.current === "summary") backHome();
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
        case "w":
          toggleWatch();
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
  }, [start, stop, backHome, toggleMute, toggleMetronome, toggleCamera, toggleWatch]);

  const camPill: PillState =
    view?.camStatus === "on" ? (view.cam.posture?.visible ? "on" : "warn") : view?.camStatus === "starting" ? "warn" : "off";
  const live = view?.live;
  const bs = view?.backend;
  const watchLabel = bs?.sources.source === "sim" ? "Watch (sim)" : bs?.sources.source === "replay" ? "Watch (replay)" : "Watch";
  const showGauges = phase === "countdown" || phase === "running";

  return (
    <div className="app">
      <header className="topbar">
        <h1 className="brand">CPR Coach</h1>
        <StatusPills
          pills={[
            { label: "Backend", state: view?.backendUp ? "on" : "off" },
            { label: useWatch ? watchLabel : "Watch ignored [W]", state: !useWatch ? "off" : bs?.sources.watch_streaming ? "on" : "off" },
            { label: "Phone", state: bs?.sources.phone_connected ? "on" : "off" },
            { label: "Camera", state: camPill },
          ]}
        />
        <div className="toggles">
          <span className={metronomeOn ? "on" : ""}>
            Metronome {metronomeOn ? "on" : "off"} <kbd>B</kbd>
          </span>
          <span className={muted ? "" : "on"}>
            Voice {muted ? "off" : "on"} <kbd>M</kbd>
          </span>
        </div>
        <div className="clocks">
          {phase === "running" && live?.rate.source === "watch" && bs && (
            <Timer seconds={bs.session.cycle_elapsed_s} label="Rescuer" />
          )}
          <Timer seconds={view?.elapsed ?? 0} label="Session" />
        </div>
      </header>

      <CoachBanner
        rule={phase === "running" ? banner : null}
        idleText={
          phase === "countdown"
            ? "Get ready"
            : phase === "running"
              ? "Keep going"
              : phase === "calibrate"
                ? "Calibrating"
                : "Enter a name and press Start"
        }
      />

      <main className="stage">
        <div className="camera-wrap">
          <CameraView ref={videoRef} canvasRef={canvasRef} status={view?.camStatus ?? "off"} error={view?.camError ?? null} />
          {phase === "countdown" && (
            <div className="countdown">
              <span key={countdown}>{countdown > 0 ? countdown : "Go"}</span>
            </div>
          )}
          {phase === "running" && name && <div className="rescuer-tag">{name}</div>}
        </div>
        {showGauges && (
          <div className="side">
            <div className="params">
              <RateGauge cpm={live?.rate.cpm ?? null} source={live?.rate.source ?? null} />
              <DepthBar cm={live?.depth.cm ?? null} estimate={live?.depth.estimate ?? false} source={live?.depth.source ?? null} />
            </div>
            <section className="trace" aria-label="Compression trace">
              <Waveform
                samples={view?.wave.samples ?? []}
                ticks={view?.wave.ticks ?? []}
                now={view?.wave.now ?? 0}
                spanS={CAMERA_COMPRESSIONS.traceS}
              />
              <span className="trace-label">
                {view?.wave.label ?? ""} · {live?.compressionCount ?? 0} compressions
              </span>
            </section>
          </div>
        )}
        {(phase === "home" || phase === "summary") && (
          <HomePanel
            name={name}
            onName={setName}
            onStart={start}
            onCalibrate={() => setPhase("calibrate")}
            board={board}
            calibration={calibration}
            error={homeError}
          />
        )}
        {phase === "calibrate" && (
          <CalibrationWizard
            step={cal.step}
            cameraVisible={(view?.cam.on ?? false) && (view?.cam.posture?.visible ?? false)}
            watchStreaming={bs?.sources.watch_streaming ?? false}
            using={cal.using}
            counts={cal.counts}
            result={cal.result}
            saving={cal.saving}
            error={cal.error}
            onBegin={beginCalibration}
            onFinishNow={finishCalibration}
            onSave={saveCalibration}
            onRetry={beginCalibration}
            onCancel={cancelCalibration}
          />
        )}
      </main>

      {live && <PostureChecklist live={live} />}

      <footer className="footer">
        <span>Training tool, not a medical device.</span>
        <span className="keys">
          <kbd>Space</kbd> start/stop <kbd>S</kbd> swap <kbd>C</kbd> camera <kbd>W</kbd> watch <kbd>D</kbd> debug <kbd>F</kbd> fullscreen
        </span>
      </footer>

      {phase === "summary" && (
        <SummaryCard summary={summary} error={summaryError} added={added} onAdd={addToLeaderboard} onAgain={backHome} />
      )}

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
            `backend ws    ${view.backendUp ? "up" : "down"}  source=${bs?.sources.source ?? "—"}  session=${bs?.session.status ?? "—"}`,
            `packets       ${bs?.sources.packet_rate_hz.toFixed(1) ?? "—"}/s  gaps=${bs?.sources.gaps ?? "—"}  age=${bs?.sources.last_packet_age_ms ?? "—"} ms  watch reachable=${bs?.sources.watch_reachable ?? "—"}`,
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
