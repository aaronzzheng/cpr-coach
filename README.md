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

Keyboard: `Space` start/stop · `B` metronome · `M` mute voice · `C` camera on/off · `D` debug overlay · `F` fullscreen.

- Simulator: `make sim SCENARIO=shallow` *(M2)*
- Tests: `make test`
- Production build: `make build`, then the backend serves `web/dist` at http://localhost:8000

## Calibrate

*(M4)*

## Demo

*(M5)*

## Troubleshooting

*(M5)*
