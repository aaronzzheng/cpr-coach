# CPR Coach: laptop dashboard and web version

Real-time CPR feedback from an Apple Watch, a webcam and a laptop. **Training tool – not a medical device.**

See [PRD.md](../PRD.md) for the full spec. Back to the [main README](../README.md).

## Setup

Requires Python 3.11+ and Node 20+.

```bash
make setup
mkdir -p web/public/models && curl -L -o web/public/models/pose_landmarker_full.task \
  https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_full/float16/latest/pose_landmarker_full.task
```

`npm install` copies MediaPipe's wasm into `web/public/wasm`, so pose runs with no internet.

## Run

```bash
make dev
```

Opens the dashboard at http://localhost:5173 (API on :8000, bound to 0.0.0.0 so the phone can reach it).

Camera-only mode (no Apple hardware): put the laptop so the webcam sees you **from the side**, kneeling at a cushion with your whole upper body in frame. Allow camera access, press **Space**, and do compressions. Depth shows as `~` because it's an estimate from your arm length until calibration (M4) exists.

Keyboard: `Space` start/stop · `S` swap rescuer · `B` metronome · `M` mute voice · `C` camera on/off · `D` debug overlay · `F` fullscreen.

- Simulator (no watch needed): with `make dev` running, in another terminal
  `make sim SCENARIO=shallow`. Scenarios: `good`, `shallow`, `fast`, `slow`, `fatigue`, `chaotic`.
  For live tweaking: `cd backend && .venv/bin/python -m tools.sim_watch --interactive`
  (`+`/`-` rate, `[`/`]` depth, `p` pause, `q` quit). See `--help` for all flags.
- Tests: `make test`
- Production build: `make build`, then the backend serves `web/dist` at http://localhost:8000

Real watch: follow [apple/SETUP.md](../apple/SETUP.md) (Xcode project, signing, devices, then connect the iPhone relay to `ws://<laptop IP>:8000/ingest`).

## Calibrate

Do this before demos (about 60 s). You need a ruler taped beside the cushion.

1. On the home screen click **Calibrate**.
2. **Framing:** kneel beside the cushion until the wizard shows *Arm visible* (and *Watch streaming* if you're wearing it).
3. **5 cm compressions:** do 10 compressions pressing exactly 5 cm against the ruler, following the metronome.
4. **Result:** check the *depth check* reads about 5.0 cm, then **Save**. A scale outside ×0.5–×2.0 means something went wrong: try again.

Calibration is stored in `data/calibration.json` and applies immediately.

## Sessions, scores and replay

- Home → type a name → **Start** (or Enter/Space). There's a 3 s countdown, then coaching. **Space** stops and shows the scorecard.
- Score (0–100): 30 % rate in range, 30 % depth in range, 20 % compression fraction (vs. 80 %), 10 % elbows locked, 10 % shoulders over hands. Missing terms are dropped and the rest reweighted. The watch is used when it saw at least 10 compressions; otherwise the camera.
- **Add to leaderboard** keeps the top 10 in `data/leaderboard.json` (survives restarts).
- Every session's raw watch stream is recorded to `data/sessions/<id>/stream.jsonl`. Replay one into the dashboard as if the watch were live:

  ```bash
  make replay SESSION=data/sessions/2026-10-24T15-02-11
  ```

  Add `SPEED=2` to play faster, or run `cd backend && .venv/bin/python -m tools.replay --help` for `--loop`.

## Demo

### Before judging

1. `make demo` serves everything from one process on port 8000: no auto-reload, built dashboard, works with no internet. Open http://localhost:8000 on the projector and press **F** for fullscreen. (Don't demo from `make dev`: it restarts the backend whenever a file changes, which ends the session in progress.)
2. Camera on a stand **to the side**, rescuer's whole upper body in frame, good light.
3. Watch: iPhone relay connected (*Socket: connected*) and **left open on screen**, watch app **Start** pressed. The **Watch** and **Phone** pills are green. On the watch, set Settings → General → **Return to Clock → CPR Coach → After 1 hour** and Display → **Wake Duration → 70 s**, so the app stays in front. When it isn't in front, the watch reports the phone unreachable and drops data.
4. Run **Calibrate** with the ruler (about 60 s).
5. Do one 20-second practice run and check the voice and metronome are audible.

### Operator keys

| Key | Action |
|---|---|
| `Space` | start / stop session (on the scorecard: back to home) |
| `S` | swap rescuers (resets the fatigue cycle) |
| `B` | metronome on/off (laptop and watch) |
| `M` | mute the voice coach |
| `W` | **ignore the watch**: camera-only backup mode (the scorecard then uses camera metrics too) |
| `C` | camera on/off |
| `D` | debug overlay (pose fps, packet rate, gaps, raw metrics) |
| `F` | fullscreen |

### 3-minute script

1. **Hook (20 s):** most bystanders push too shallow and too slow, and quality falls apart within about 2 minutes. *(Check the exact statistics before pitching.)*
2. **Live run (60 s):** a teammate goes deliberately shallow → "Push harder" → corrects. Bends their elbows → "Lock your elbows" → corrects.
3. **Fatigue (20 s):** replay the fatigue recording: `make replay SESSION=recordings/fatigue.jsonl SPEED=4`. "Switch rescuers" appears, and the scorecard marks when fatigue was detected.
4. **Judge (60 s):** a judge types their name, does 30 s, gets a score, clicks **Add to leaderboard**.
5. **Tech (20 s):** 100 Hz IMU projected onto gravity, per-cycle double integration with zero-velocity resets, MediaPipe pose for form, all on-device.

### Backup plan

- **Watch fails live:** press `W`. Rate, estimated depth and posture keep coming from the camera.
- **Everything fails:** `make replay SESSION=recordings/good.jsonl` (or `fatigue.jsonl`) drives the dashboard exactly as the watch would.
- Record real golden sessions with the watch before the event: `make record NAME=good`, then do compressions and press Enter. The checked-in recordings come from the simulator.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Dashboard says *Camera error: Permission denied* | Allow the camera for localhost in the browser's site settings, then reload. |
| Camera pill is amber | The arm isn't visible enough. Use a side view, show shoulder to wrist, add light, wear contrasting sleeves. |
| Compressions not counted from the camera | Press `D`: *cam amp px* should be well above the jitter. Move the camera closer or reframe. |
| Watch pill off but phone connected | Tap the watch so CPR Coach is showing, and press Start if it's stopped. Press `D`: if *watch reachable=false*, the watch app isn't in front (see the Return to Clock setting above) or the iPhone relay is in the background. |
| Phone can't reach the laptop | Hackathon Wi-Fi blocks device-to-device traffic: use the iPhone Personal Hotspot (see `apple/SETUP.md`). |
| Watch rate jumpy or misses compressions | Lower the peak threshold: `CPR_PEAK_PROMINENCE=2.0 make demo` (default 3.0 m/s²). |
| Depth always too high/low | Re-run **Calibrate** with the ruler. |
| No voice | Click the page once (browsers block audio until you interact), check `M` isn't muted. |
| Scorecard says *Couldn't score this session* | The backend restarted during the session (for example `make dev` reloading). Use `make demo`. |
| Leaderboard or calibration looks wrong | They're plain JSON in `data/`. Delete `data/leaderboard.json` or `data/calibration.json` to reset. |
