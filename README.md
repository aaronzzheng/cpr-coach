# CPR Coach

Real-time CPR feedback from an Apple Watch, a webcam and a laptop. **Training tool – not a medical device.**

See [PRD.md](PRD.md) for the full spec.

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

Real watch: follow [apple/SETUP.md](apple/SETUP.md) (Xcode project, signing, devices, then connect the iPhone relay to `ws://<laptop IP>:8000/ingest`).

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

*(M5)*

## Troubleshooting

*(M5)*
