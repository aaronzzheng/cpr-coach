// Dashboard shell: owns the camera pipeline, backend socket, fusion/coach tick loop, metronome
// and speech, and the home → calibrate / countdown → running → summary flow (PRD §8.1).
import { Check, Heart, HeartPulse, Mic, Music, Volume2, VolumeX } from "lucide-react";
import { useCallback, useEffect, useRef, useState } from "react";
import { Metronome } from "./audio/metronome";
import { computeCalibration, type CalibrationResult } from "./calibration/calibrate";
import { CoachEngine } from "./coach/coachEngine";
import type { Rule } from "./coach/rules";
import { Speech } from "./coach/speech";
import { CalibrationWizard, type CalibrationStep } from "./components/CalibrationWizard";
import { CameraView } from "./components/CameraView";
import { CoachBanner } from "./components/CoachBanner";
import { HandoffSheet, type TimelineEvent } from "./components/HandoffSheet";
import { LanguageMenu } from "./components/LanguageMenu";
import { HomePanel } from "./components/HomePanel";
import { PostureChecklist } from "./components/PostureChecklist";
import { MetricTile } from "./components/MetricTile";
import { StatusPills, type PillState } from "./components/StatusPills";
import { SummaryCard } from "./components/SummaryCard";
import { Timer } from "./components/Timer";
import { Waveform, type WaveSample } from "./components/Waveform";
import { CALIBRATION, CAMERA_COMPRESSIONS, COACH, COUNTDOWN_S, TARGETS, UI_TICK_MS } from "./config";
import { SwapForecaster } from "./fusion/forecast";
import { cameraCmPerPx, fuse, type CameraSnapshot, type LiveState } from "./fusion/fuse";
import { LANG_INFO, lang as currentLang, num, setLang, t, type Lang } from "./i18n";
import { api, type Calibration, type LeaderboardEntry, type Summary } from "./net/api";
import { BackendSocket } from "./net/backendSocket";
import type { CompressionMsg, StateMsg } from "./net/messages";
import { CameraPipeline, type CameraStatus } from "./pose/cameraPipeline";
import { depthMax, depthMin, setPatient, type Patient } from "./patient";
import { SessionTracker } from "./session/sessionTracker";
import { SKILLS } from "./session/skills";
import { matchCommand, VoiceListener, type VoiceCommand } from "./voice/commands";

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

/** 30:2 mode: compressions per cycle, the longest breath pause, and how soon a compression ends it. */
const BREATHS = { compressions: 30, maxPauseS: 10, resumeAfterS: 1.5 } as const;

export default function App() {
  const videoRef = useRef<HTMLVideoElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const pipeline = useRef<CameraPipeline | null>(null);
  const engine = useRef(new CoachEngine());
  const speech = useRef<Speech | null>(null);
  const metronome = useRef(new Metronome());
  const backend = useRef(new BackendSocket());
  const tracker = useRef<SessionTracker | null>(null);
  const forecaster = useRef(new SwapForecaster());
  const listener = useRef<VoiceListener | null>(null);
  const events = useRef<TimelineEvent[]>([]);
  const swaps = useRef(0);
  const cycleCount = useRef(0);
  const breathSince = useRef<number | null>(null);
  const skillsRef = useRef(false);

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
  const [language, setLanguage] = useState<Lang>(currentLang());
  const [patient, setPatientState] = useState<Patient>("adult");
  const [breathsMode, setBreathsMode] = useState(false);
  const [handsFree, setHandsFree] = useState(VoiceListener.supported);
  const [skills, setSkills] = useState(false);
  const [heard, setHeard] = useState<string | null>(null);
  const [showHandoff, setShowHandoff] = useState(false);
  const breathsRef = useRef(false);
  breathsRef.current = breathsMode;
  skillsRef.current = skills;

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
  const viewRef = useRef<View | null>(null);
  viewRef.current = view;
  const bannerRef = useRef<Rule | null>(null);
  bannerRef.current = banner;
  const metronomeOnRef = useRef(true);
  metronomeOnRef.current = metronomeOn;
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
        // Fatigue forecast on the watch's per-compression depths (backend clock).
        for (const e of watchEvents) if (e.depth_cm !== null) forecaster.current.push(e.t, e.depth_cm);
        live.swapInS = bNow !== null && live.depth.source === "watch" ? forecaster.current.update(bNow, depthMin()) : null;

        // 30:2: count compressions from whichever source leads; pause for breaths every 30.
        const fresh = live.rate.source === "watch" && bNow !== null ? watchEvents.map((e) => now - (bNow - e.t)) : camEvents.map((c) => c.t);
        for (const ct of fresh) {
          const since = breathSince.current;
          if (since !== null) {
            if (ct - since < BREATHS.resumeAfterS) continue;
            endBreaths(false); // compressions resumed on their own
          }
          cycleCount.current += 1;
          if (breathsRef.current && cycleCount.current >= BREATHS.compressions) beginBreaths(now);
        }
        if (breathSince.current !== null && now - breathSince.current > BREATHS.maxPauseS) endBreaths(true);
        live.breathPause = breathSince.current !== null;

        if (skillsRef.current && tr.elapsed(now) >= SKILLS.durationS) stopRef.current();
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
        if (d.speak) speech.current?.say(t(d.speak.line), d.speak.priority);
      }
    }, UI_TICK_MS);
    return () => clearInterval(id);
  }, [finishCalibration]);

  const start = useCallback((skillsCheck = false) => {
    if (phaseRef.current !== "home") return;
    // Runs inside a user gesture, which unlocks audio and speech for the rest of the session.
    metronome.current.prime();
    setSkills(skillsCheck);
    speech.current?.say(t("Get ready."), 0);
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
      forecaster.current.reset();
      engine.current.reset();
      pipeline.current?.resetSession();
      sessionId.current = null;
      watchOverridden.current = !useWatchRef.current;
      events.current = [{ at: new Date(), label: t("Compressions started") }];
      swaps.current = 0;
      cycleCount.current = 0;
      breathSince.current = null;
      api.startSession(name, patient).then(
        (r) => (sessionId.current = r.session_id),
        (e: Error) => setHomeError(`Backend: ${e.message}`),
      );
      if (metronomeOn) metronome.current.start();
      speech.current?.say(t("Start compressions."), 0);
      setPhase("running");
    }, 1000);
  }, [metronomeOn, name, patient]);

  const stop = useCallback(() => {
    if (countdownTimer.current) clearInterval(countdownTimer.current);
    metronome.current.stop();
    setBanner(null);
    if (phaseRef.current === "countdown") {
      setPhase("home");
      return;
    }
    if (phaseRef.current !== "running") return;
    breathSince.current = null;
    events.current.push({ at: new Date(), label: t("Compressions stopped") });
    const cam = tracker.current?.finish(nowS(), watchOverridden.current);
    setSummary(null);
    setSummaryError(null);
    setAdded(false);
    setPhase("summary");
    speech.current?.say(t("Stop. Well done."), 0);
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
  const stopRef = useRef(stop);
  stopRef.current = stop;

  // Rescue breaths (30:2): metronome off, a planned pause that doesn't count against hands-on time.
  function beginBreaths(now: number) {
    breathSince.current = now;
    cycleCount.current = 0;
    if (tracker.current) tracker.current.plannedPause = true;
    backend.current.send({ cmd: "planned_pause" });
    metronome.current.stop();
    speech.current?.say(t("Give 2 breaths."), 0);
    engine.current.markSpoken("breaths", now);
  }

  function endBreaths(prompt: boolean) {
    if (breathSince.current === null) return;
    breathSince.current = null;
    if (metronomeOnRef.current && phaseRef.current === "running") metronome.current.start();
    if (prompt) speech.current?.say(t("Resume compressions now."), 0);
  }

  const swapRescuers = useCallback(() => {
    backend.current.send({ cmd: "swap" });
    forecaster.current.reset();
    if (phaseRef.current === "running") {
      swaps.current += 1;
      events.current.push({ at: new Date(), label: t("Rescuers switched") });
    }
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
          swapRescuers();
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
  }, [start, stop, backHome, toggleMute, toggleMetronome, toggleCamera, toggleWatch, swapRescuers]);

  // Hands-free voice commands while running.
  const showHeard = useRef<ReturnType<typeof setTimeout> | null>(null);
  const onCommand = useCallback(
    (cmd: VoiceCommand) => {
      const label = { stop: "Stop", swap: "Swap", time: "How long", status: "How am I doing", done: "Done" }[cmd];
      setHeard(t(label));
      if (showHeard.current) clearTimeout(showHeard.current);
      showHeard.current = setTimeout(() => setHeard(null), 2500);
      const v = viewRef.current;
      switch (cmd) {
        case "stop":
          stop();
          break;
        case "swap":
          swapRescuers();
          speech.current?.say(t("Switch now. Next rescuer, start compressions."), 0);
          break;
        case "time": {
          const s = Math.floor(v?.elapsed ?? 0);
          const n = v?.live.compressionCount ?? 0;
          speech.current?.say(s >= 60 ? t("%@ minutes %@ seconds, %@ compressions.", Math.floor(s / 60), s % 60, n) : t("%@ seconds, %@ compressions.", s, n), 0);
          break;
        }
        case "status": {
          const l = v?.live;
          const parts: string[] = [];
          if (l?.rate.cpm != null) parts.push(t("Rate %@.", Math.round(l.rate.cpm)));
          if (l?.depth.cm != null && l.depth.drivesCoach) parts.push(t("Depth %@ centimeters.", num(l.depth.cm, 1)));
          if (!parts.length) parts.push(t("I can't see compressions yet. Push hard and fast."));
          else parts.push(bannerRef.current && bannerRef.current.id !== "praise" ? t(bannerRef.current.line) : t("Looking good, keep going."));
          speech.current?.say(parts.join(" "), 0);
          break;
        }
        case "done":
          endBreaths(true);
          break;
      }
    },
    [stop, swapRescuers],
  );

  useEffect(() => {
    const want = phase === "running" && handsFree && VoiceListener.supported;
    if (!want) {
      listener.current?.stop();
      return;
    }
    const l = new VoiceListener(
      (text) => {
        const cmd = matchCommand(text, language, breathSince.current !== null);
        if (!cmd) return false;
        onCommand(cmd);
        return true;
      },
      () => speech.current?.echoWindow ?? false,
    );
    listener.current = l;
    l.start(LANG_INFO[language].bcp47);
    return () => l.stop();
  }, [phase, handsFree, language, onCommand]);

  const changeLanguage = useCallback((l: Lang) => {
    setLang(l);
    setLanguage(l);
    speech.current?.pick();
  }, []);

  const changePatient = useCallback((p: Patient) => {
    setPatient(p);
    setPatientState(p);
  }, []);

  const camPill: PillState =
    view?.camStatus === "on" ? (view.cam.posture?.visible ? "on" : "warn") : view?.camStatus === "starting" ? "warn" : "off";
  const live = view?.live;
  const bs = view?.backend;
  const watchLabel = bs?.sources.source === "sim" ? `${t("Watch")} (sim)` : bs?.sources.source === "replay" ? `${t("Watch")} (replay)` : t("Watch");
  const showGauges = phase === "countdown" || phase === "running";

  return (
    <div className="app">
      <header className="topbar">
        <div className="brand">
          <HeartPulse size={22} strokeWidth={2.25} aria-hidden="true" />
          CPR Coach
        </div>
        <StatusPills
          pills={[
            { label: useWatch ? watchLabel : t("Watch ignored"), state: !useWatch ? "off" : bs?.sources.watch_streaming ? "on" : "off" },
            { label: t("Phone"), state: bs?.sources.phone_connected ? "on" : "off" },
            { label: t("Camera"), state: camPill },
            { label: t("Server"), state: view?.backendUp ? "on" : "off" },
          ]}
        />
        <div className="topbar-right">
          {phase === "running" && handsFree && listener.current?.listening && (
            <span className={`heard ${heard ? "ok" : ""}`} role="status">
              {heard ? <Check size={16} aria-hidden="true" /> : <Mic size={16} aria-hidden="true" />}
              {heard ?? t("Listening")}
            </span>
          )}
          {(phase === "home" || phase === "summary") && <LanguageMenu value={language} onChange={changeLanguage} />}
          {live?.hrBpm != null && (
            <span className="hr" aria-label={t("Heart rate %@", live.hrBpm)}>
              <Heart size={18} fill="currentColor" aria-hidden="true" />
              {live.hrBpm}
            </span>
          )}
          <button className={`icon-btn ${metronomeOn ? "on" : ""}`} onClick={toggleMetronome} aria-pressed={metronomeOn} title={`${t("Metronome")} (B)`}>
            <Music size={20} aria-hidden="true" />
            <span className="sr-only">{t("Metronome")}</span>
          </button>
          <button className={`icon-btn ${muted ? "" : "on"}`} onClick={toggleMute} aria-pressed={!muted} title={`${t("Voice coach")} (M)`}>
            {muted ? <VolumeX size={20} aria-hidden="true" /> : <Volume2 size={20} aria-hidden="true" />}
            <span className="sr-only">{t("Voice coach")}</span>
          </button>
          {phase === "running" && live?.rate.source === "watch" && bs && (
            <Timer seconds={bs.session.cycle_elapsed_s} label={t("Rescuer")} />
          )}
          {/* A skills check counts down its 2 minutes; otherwise the session clock counts up. */}
          <Timer
            seconds={skills && phase === "running" ? Math.max(0, SKILLS.durationS - (view?.elapsed ?? 0)) : (view?.elapsed ?? 0)}
            label={skills && phase === "running" ? t("Skills check") : t("Session")}
          />
        </div>
      </header>

      {(phase === "countdown" || phase === "running") && (
        <CoachBanner
          rule={phase === "running" ? banner : null}
          detail={phase === "running" ? instructionDetail(banner?.id ?? null, live) : null}
          idleText={phase === "countdown" ? t("Get ready") : t("Keep going")}
        />
      )}

      <main className="stage">
        <div className="camera-wrap">
          <CameraView ref={videoRef} canvasRef={canvasRef} status={view?.camStatus ?? "off"} error={view?.camError ?? null} />
          {phase === "countdown" && (
            <div className="countdown">
              <span key={countdown}>{countdown > 0 ? countdown : t("Go")}</span>
            </div>
          )}
          {phase === "running" && name && <div className="rescuer-tag">{name}</div>}
        </div>
        {showGauges && (
          <div className="side">
            <div className="params">
              <MetricTile
                label={t("Rate")}
                value={live?.rate.cpm ?? null}
                unit={t("/min")}
                scale={[80, 140]}
                target={[TARGETS.rate_min_cpm, TARGETS.rate_max_cpm]}
                outWords={[t("Too slow"), t("Too fast")]}
                source={live?.rate.source ?? null}
              />
              <MetricTile
                label={t("Depth")}
                value={live?.depth.cm ?? null}
                digits={1}
                unit="cm"
                scale={[0, 8]}
                target={[depthMin(), depthMax()]}
                outWords={[t("Too shallow"), t("Too deep")]}
                source={live?.depth.source ?? null}
                estimate={live?.depth.estimate ?? false}
              />
            </div>
            <section className="trace" aria-label={t("Compressions")}>
              <Waveform
                samples={view?.wave.samples ?? []}
                ticks={view?.wave.ticks ?? []}
                now={view?.wave.now ?? 0}
                spanS={CAMERA_COMPRESSIONS.traceS}
              />
              <header className="trace-head">
                <h2 className="tile-label">{t("Compressions")}</h2>
                <span className="meta">{t("%@ so far", live?.compressionCount ?? 0)}</span>
              </header>
            </section>
          </div>
        )}
        {(phase === "home" || phase === "summary") && (
          <HomePanel
            name={name}
            onName={setName}
            onStart={() => start(false)}
            onSkills={() => start(true)}
            onCalibrate={() => setPhase("calibrate")}
            patient={patient}
            onPatient={changePatient}
            breaths={breathsMode}
            onBreaths={setBreathsMode}
            handsFree={handsFree}
            onHandsFree={setHandsFree}
            voiceSupported={VoiceListener.supported}
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

      {live && (phase === "countdown" || phase === "running" || phase === "calibrate") && <PostureChecklist live={live} />}

      <footer className="footer">
        <span>{t("Training tool, not a medical device.")}</span>
        <span>{t("Space start or stop · S swap rescuer · W ignore watch · C camera · D details · F full screen")}</span>
      </footer>

      {phase === "summary" && (
        <SummaryCard
          summary={summary}
          error={summaryError}
          added={added}
          onAdd={addToLeaderboard}
          onAgain={backHome}
          skills={skills}
          onHandoff={() => setShowHandoff(true)}
        />
      )}
      {phase === "summary" && showHandoff && summary && (
        <HandoffSheet events={events.current} summary={summary} swaps={swaps.current} onClose={() => setShowHandoff(false)} />
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

/** One line of specifics under the instruction, from the live numbers. */
function instructionDetail(ruleId: string | null, live: LiveState | undefined): string | null {
  if (!live) return null;
  const rate = live.rate.cpm === null ? null : Math.round(live.rate.cpm);
  const depth = live.depth.cm === null ? null : `${live.depth.estimate ? "≈" : ""}${num(live.depth.cm, 1)} cm`;
  switch (ruleId) {
    case "too_shallow":
    case "too_deep":
      return depth !== null ? t("Depth %@. Aim for %@ cm.", depth, `${num(depthMin(), 1)}–${num(depthMax(), 1)}`) : null;
    case "too_slow":
    case "too_fast":
      return rate !== null ? t("%@ per minute. Aim for 100–120, follow the beat.", rate) : null;
    case "elbows_bent":
      return live.posture.elbowAngleDeg !== null ? t("Elbows at %@°. Straighten your arms.", Math.round(live.posture.elbowAngleDeg)) : null;
    case "not_over_hands":
      return t("Lean forward so your shoulders are above your hands.");
    case "incomplete_recoil":
      return t("Lift your weight off the chest between pushes, but keep your hands on it.");
    case "swap_soon":
      return live.swapInS !== null ? t("Depth is trending down: below %@ cm in about %@ s.", num(depthMin(), 1), Math.round(live.swapInS)) : null;
    case "breaths":
      return t("Tilt the head back, lift the chin, 2 breaths of 1 second each. Then straight back to compressions.");
    case "swap":
      return t("Hand over to the next person without pausing.");
    case "no_compressions":
      return t("Every second without compressions counts.");
    case "praise":
      return rate !== null && depth !== null ? t("%@ per minute at %@.", rate, depth) : null;
    default:
      return rate !== null ? (depth ? t("%@ per minute at %@.", rate, depth) : t("%@ per minute.", rate)) : null;
  }
}
