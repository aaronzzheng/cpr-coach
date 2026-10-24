# PRD: CPR Coach

Real-time CPR feedback using an Apple Watch, a camera, and a laptop.

> **Build notes:** This project is built from scratch at a hackathon. Read this whole document before writing code. Follow the build order in §12 exactly. **Milestone 1 must work with no Apple hardware at all.** Never block progress on the watch. When a step needs hands-on work (Xcode project creation, signing, device pairing), write exact click-by-click instructions, then continue on the other parts. Commit after every milestone.

---

## 0. TL;DR

A bystander does chest compressions on a CPR manikin or a firm cushion. Three devices work together:

- **Apple Watch** on the rescuer's wrist. It streams 100 Hz motion data and gives haptic metronome taps on the wrist.
- **Laptop webcam** with a side view of the rescuer. Pose estimation checks arm and body posture.
- **Laptop** runs the signal processing and a full-screen dashboard. A voice coach says things like "Push harder", "Slow down", "Lock your elbows" and "Switch rescuers now".

At the end of a session, the dashboard shows a scorecard measured against AHA adult CPR targets. A leaderboard lets judges compete.

**Pitch line:** "Bystander CPR roughly doubles to triples survival from cardiac arrest, but most people don't push hard or fast enough, and they get tired within 2 minutes without noticing. CPR Coach turns the watch on your wrist into a real-time CPR instructor."

---

## 1. Goals and non-goals

### Goals (must ship)

1. Live **compression rate** in compressions per minute (cpm), accurate to ±3 cpm, from the watch, with the camera as a fallback.
2. Live **compression depth** in cm per compression, from watch accelerometer integration. Calibrated accuracy target is ±1 cm.
3. Live **posture checks** from the camera: elbows locked and shoulders over hands.
4. **Hands-off time and pause detection**, plus chest compression fraction (CCF, the share of time spent compressing).
5. **Voice coaching** with priority and cooldown rules.
6. A **metronome at 110 BPM**: audio on the laptop and haptic on the watch.
7. **Fatigue detection**, which prompts "Switch rescuers" when depth drops or at the 2-minute mark.
8. A **session summary scorecard** (0–100) plus a **judge leaderboard**.
9. A **watch simulator** and **session recording and replay**, so everything can be developed and demoed without the watch.

### Non-goals

- Not a medical device. It makes no clinical claims. The UI must say "Training tool – not a medical device."
- No user accounts, no cloud, and no data leaves the laptop.
- No Android support.
- No phone-side ML. The phone is only a relay; see §3.

---

## 2. Hardware and environment

| Item | Details |
|---|---|
| Apple Watch | **Model A2157 = Series 5, 44 mm, GPS + Cellular.** Highest supported watchOS is **10.x**, so set the watch app's deployment target to **watchOS 10.0**. It has an accelerometer, gyroscope, optical heart rate sensor and Taptic Engine. The 800 Hz `CMBatchedSensorManager` is **not** available because it needs Series 8 or later. Use `CMMotionManager` deviceMotion at **100 Hz**. |
| iPhone | Paired with the watch. It runs the relay app. |
| Laptop | A Mac is required for Xcode. It runs the Python backend, the web dashboard and the webcam. |
| Practice "chest" | A CPR manikin if one is available. Otherwise a firm couch cushion or a rolled jacket on the floor, with a ruler taped beside it for calibration and proof. |
| Network | Phone and laptop must be on the same network. **Hackathon Wi-Fi often blocks device-to-device traffic (client isolation).** The fallback is to turn on the iPhone Personal Hotspot and join it from the laptop. See §9.4. |

---

## 3. System architecture

```
┌──────────────────────┐   WatchConnectivity    ┌──────────────────────┐   WebSocket (JSON)    ┌─────────────────────────────────────┐
│  Apple Watch app     │  sendMessageData       │  iPhone relay app    │  ws://LAPTOP:8000/    │  Laptop                              │
│  (watchOS 10, Swift) │ ─────────────────────▶ │  (iOS, SwiftUI)      │  ingest               │                                      │
│                      │   ~5 msgs/s, 20 samp   │                      │ ────────────────────▶ │  Python backend (FastAPI)            │
│ • HKWorkoutSession   │                        │ • WCSession delegate │                       │  • ingest + seq/gap tracking         │
│ • CMMotionManager    │ ◀───────────────────── │ • URLSessionWebSocket│ ◀──────────────────── │  • DSP: filter, peaks, depth         │
│   100 Hz deviceMotion│   commands (start/stop │ • status UI          │   commands            │  • fatigue model                     │
│ • Heart rate (HK)    │   metronome on/off)    │ • idle timer off     │                       │  • recorder (JSONL)                  │
│ • Haptic metronome   │                        └──────────────────────┘                       │  • broadcasts state @ 20 Hz          │
└──────────────────────┘                                                                       │            │ ws://localhost:8000/ws  │
                                                                                               │            ▼                         │
                                                                                               │  Web dashboard (Vite+React+TS)       │
                                                                                               │  • webcam + MediaPipe Pose (in-browser)
                                                                                               │  • posture metrics                   │
                                                                                               │  • fusion + coach engine + TTS       │
                                                                                               │  • metronome audio                   │
                                                                                               │  • UI, summary, leaderboard          │
                                                                                               └─────────────────────────────────────┘
```

### Key design decisions (do not change without a reason)

1. **The watch never talks to the laptop directly.** watchOS restricts low-level networking such as WebSockets for most apps (Apple TN3135). All data goes through the iPhone over WatchConnectivity.
2. **The camera pose runs in the browser** using `@mediapipe/tasks-vision` PoseLandmarker. No video is streamed anywhere. The skeleton overlay is drawn on a canvas over the `<video>` element.
3. **Watch DSP runs in Python** (numpy and scipy) so it's easy to tune and unit test.
4. **Fusion and the coach engine run in the frontend**, which has both the watch state from the backend and the camera metrics computed locally.
5. **Everything degrades gracefully.** No watch means camera-only mode. No camera means watch-only mode. Neither means the simulator. The dashboard always shows source status pills.

---

## 4. Medical targets (AHA adult CPR guidance)

Hard-code these in **one** config file (`shared/targets.json`, read by both the backend and the frontend):

```json
{
  "rate_min_cpm": 100,
  "rate_max_cpm": 120,
  "rate_target_cpm": 110,
  "depth_min_cm": 5.0,
  "depth_max_cm": 6.0,
  "pause_threshold_s": 2.0,
  "max_hands_off_s": 10.0,
  "ccf_target": 0.80,
  "rescuer_swap_s": 120,
  "elbow_locked_min_deg": 160,
  "shoulder_over_hands_max_deg": 15
}
```

---

## 5. Repository layout

```
cpr-coach/
├── PRD.md
├── README.md                     # setup + run instructions (write this as you go)
├── Makefile                      # make dev | make sim | make test | make build
├── shared/
│   └── targets.json
├── backend/
│   ├── pyproject.toml / requirements.txt   # fastapi, uvicorn[standard], numpy, scipy, pydantic, pytest
│   ├── app/
│   │   ├── main.py               # FastAPI app, routes, websockets, static serving
│   │   ├── config.py             # loads targets.json, env vars
│   │   ├── models.py             # pydantic message schemas (§7)
│   │   ├── ingest.py             # parse phone frames, seq/gap detection, ring buffer
│   │   ├── dsp/
│   │   │   ├── vertical.py       # project userAcceleration onto gravity → a_up (m/s²)
│   │   │   ├── filters.py        # streaming Butterworth (sosfilt with zi state)
│   │   │   ├── compressions.py   # online peak/trough detection → Compression events
│   │   │   ├── depth.py          # per-cycle double integration with drift removal
│   │   │   └── fatigue.py        # baseline vs. recent depth, HR, cycle timer
│   │   ├── session.py            # session state machine, metrics aggregation, scoring
│   │   ├── recorder.py           # JSONL recording of raw + events
│   │   └── broadcaster.py        # 20 Hz state push to dashboard clients
│   ├── tools/
│   │   ├── sim_watch.py          # synthetic watch → connects to /ingest like the phone
│   │   └── replay.py             # replay a recorded session into /ingest at real speed
│   └── tests/
│       ├── test_vertical.py
│       ├── test_compressions.py
│       ├── test_depth.py
│       ├── test_fatigue.py
│       └── test_scoring.py
├── web/
│   ├── package.json              # vite, react, typescript, @mediapipe/tasks-vision (pin exact version)
│   ├── public/models/pose_landmarker_full.task   # download at setup; DO NOT rely on CDN at demo time
│   └── src/
│       ├── main.tsx, App.tsx
│       ├── net/backendSocket.ts  # reconnecting WS client to /ws
│       ├── pose/
│       │   ├── poseLandmarker.ts # init + per-frame detectForVideo
│       │   ├── postureMetrics.ts # elbow angle, alignment, wrist-y signal
│       │   └── cameraCompressions.ts  # fallback rate/relative depth from wrist y
│       ├── fusion/fuse.ts        # merges watch + camera into one LiveState
│       ├── coach/
│       │   ├── rules.ts          # rule table (§8.4)
│       │   ├── coachEngine.ts    # priority + cooldowns
│       │   └── speech.ts         # Web Speech API wrapper
│       ├── audio/metronome.ts    # WebAudio scheduled clicks (not setInterval)
│       ├── components/           # RateGauge, DepthBar, Waveform, PostureChecklist,
│       │                         # CoachBanner, StatusPills, Timer, HeartRate,
│       │                         # CameraView, SummaryCard, Leaderboard, CalibrationWizard
│       └── styles/
└── apple/
    ├── SETUP.md                  # click-by-click Xcode instructions for the human (§9)
    └── CPRCoach/                 # Xcode project created in Xcode; Swift sources installed from apple/Sources
        ├── CPRCoach (iOS)/
        │   ├── CPRCoachApp.swift
        │   ├── ContentView.swift
        │   ├── WatchLink.swift
        │   └── LaptopSocket.swift
        └── CPRCoach Watch App/
            ├── CPRCoachWatchApp.swift
            ├── ContentView.swift
            ├── WorkoutManager.swift
            ├── MotionStreamer.swift
            ├── Metronome.swift
            └── PhoneLink.swift
```

---

## 6. Component specs

### 6.1 Watch app (watchOS 10, SwiftUI)

**UI (one screen):**

- A large **Start / Stop** button.
- Status lines: "Phone: connected/not reachable", "Samples sent: N", "HR: 92".
- A metronome toggle, on by default.

**WorkoutManager.swift**

- Request HealthKit authorization to read `heartRate` and share `workoutType`.
- On Start: `HKWorkoutConfiguration(activityType: .other, locationType: .indoor)`, then `HKWorkoutSession`, then `associatedWorkoutBuilder()`. Set `dataSource = HKLiveWorkoutDataSource(...)`, then call `startActivity(with: Date())` and `beginCollection`.
- **Why:** an active workout session keeps the app running and the sensors at full rate when the wrist moves and the screen dims. Without it, motion updates get throttled.
- Heart rate: in `workoutBuilder(_:didCollectDataOf:)`, read `statistics(for: .heartRate)?.mostRecentQuantity()` in count/min. Send it to the phone as an `hr` message. On a Series 5 this updates every few seconds, which is fine.
- On Stop: `endCollection`, then `finishWorkout`. Saving the workout is fine, or discard it.

**MotionStreamer.swift**

- `CMMotionManager`, `deviceMotionUpdateInterval = 1.0/100.0`.
- `startDeviceMotionUpdates(using: .xArbitraryZVertical, to: queue)` on a dedicated `OperationQueue`, not main.
- For each sample, store a row of 10 Float32 values:
  `[ts, uax, uay, uaz, gx, gy, gz, rrx, rry, rrz]`
  - `ts` = `motion.timestamp` (seconds since boot, Double, cast to Float64 for ts only; see encoding below)
  - `ua*` = `userAcceleration` in **g**, gravity already removed
  - `g*` = `gravity` in g, in the device frame
  - `rr*` = `rotationRate` in rad/s
- **Batch 20 samples** (200 ms) per message, which works out to about 5 messages per second.
- **Binary encoding** for `sendMessageData`:
  - Header: magic `0x43505231` ("CPR1") as UInt32, `seq` as UInt32, `count` as UInt16, `reserved` as UInt16.
  - Then `count` rows. Each row is `ts` as Float64 followed by 9 values as Float32. That's 8 + 36 = 44 bytes per row, so 20 rows is 880 bytes plus a 12-byte header.
  - Little-endian.
- Increment `seq` on every message so the backend can detect dropped batches.
- If the phone isn't reachable, drop the batch and don't queue it. Count drops and show the number in the UI.

**PhoneLink.swift**

- `WCSession.default`, activated on launch.
- `sendMessageData(_:replyHandler: nil, errorHandler:)` for IMU batches.
- `sendMessage(["t":"hr","bpm":Int,"ts":Double], ...)` for heart rate.
- Receives commands from the phone: `{"cmd":"metronome","on":Bool,"bpm":Int}`, `{"cmd":"start"}`, `{"cmd":"stop"}`.

**Metronome.swift**

- At 110 BPM (an interval of 0.545 s), play `WKInterfaceDevice.current().play(.click)`. Use a `DispatchSourceTimer` with a leeway of 5 ms or less.
- **Risk:** the Taptic Engine may drop or merge haptics played this fast. Test on the device first. If beats get dropped, try `.start` or `.directionUp`. If it's still unreliable, tap on **every other beat** at 55 BPM and say so in the UI ("haptic every 2 beats"). The laptop audio metronome is the primary one anyway.

**Info.plist and capabilities (watch target):**

- Capabilities: **HealthKit**, and **Background Modes → Workout processing**.
- `NSHealthShareUsageDescription`, `NSHealthUpdateUsageDescription`, `NSMotionUsageDescription`.

### 6.2 iPhone relay app (iOS, SwiftUI)

**UI:**

- A text field for the laptop address (default `ws://192.168.x.x:8000/ingest`), saved in `@AppStorage`.
- A Connect / Disconnect button.
- Status: watch paired / installed / reachable, laptop socket state, messages per second in and out, and the last heart rate.
- Buttons that send commands to the watch: Start, Stop, Metronome on/off.
- Set `UIApplication.shared.isIdleTimerDisabled = true` while connected, and keep the app in the foreground during the demo.

**WatchLink.swift**

- `WCSessionDelegate`. In `session(_:didReceiveMessageData:)`, forward the raw bytes to the laptop as a **binary** WebSocket frame, prefixed with 1 byte `0x01` (IMU).
- In `session(_:didReceiveMessage:)` (heart rate), forward as a **text** frame: `{"t":"hr","bpm":..,"ts":..,"phone_rx":<Date().timeIntervalSince1970>}`.

**LaptopSocket.swift**

- `URLSessionWebSocketTask`. Auto-reconnect with backoff (0.5, 1, 2, then capped at 4 s).
- Send a ping every 5 s. Forward laptop commands (text frames `{"cmd":...}`) to the watch with `sendMessage`.
- Send a hello frame on connect: `{"t":"hello","device":"iphone","app_version":"0.1"}`.

**Info.plist (iOS target):**

- `NSLocalNetworkUsageDescription`: "Connects to the CPR Coach laptop on your local network."
- `NSAppTransportSecurity`: set `NSAllowsLocalNetworking = YES` **and** (hackathon only) `NSAllowsArbitraryLoads = YES`, so plain `ws://` to a raw IP works.
- The HealthKit capability may also be needed on the iOS target for the watch's HealthKit authorization flow. Add it to be safe.

### 6.3 Backend (Python 3.11+, FastAPI)

**Run:** `uvicorn app.main:app --host 0.0.0.0 --port 8000`. It must bind to `0.0.0.0` so the phone can reach it. Allow the macOS firewall prompt.

**Endpoints:**

| Route | Type | Purpose |
|---|---|---|
| `/ingest` | WebSocket | From the phone or simulator. Binary frames: `0x01` + IMU packet. Text frames: hello, hr. |
| `/ws` | WebSocket | To the dashboard. Pushes `state` at 20 Hz plus `compression` events as they happen. Receives `cmd` messages from the UI. |
| `/api/session/start` | POST | `{"name": "Judge Alice"}` → `{"session_id"}`. Resets metrics. |
| `/api/session/stop` | POST | Finalizes and returns the backend portion of the summary. |
| `/api/session/{id}/summary` | POST | The frontend posts camera metrics plus the final fused score, and the backend persists them. |
| `/api/leaderboard` | GET | Top 10 by score. Stored in `data/leaderboard.json`. |
| `/api/calibration` | GET/POST | `{"depth_scale": float, "cm_per_px": float}`, persisted in `data/calibration.json`. |
| `/api/health` | GET | Status of each source. |
| `/` | static | Serves `web/dist` in production mode. |

**Pipeline (per IMU packet):**

1. **Decode** the packet (§6.1 format). Check `seq`, and if there's a gap, record `gap_count++` and mark a discontinuity so DSP doesn't integrate across it.
2. **Vertical projection** (`dsp/vertical.py`):
   - `ĝ = g / |g|`, which points toward the earth in the device frame.
   - `a_down = dot(ua, ĝ) * 9.80665` in m/s².
   - `a_up = -a_down`.
   - This is orientation-independent, so the watch can be on either wrist at any angle.
   - Unit test: synthetic `ua` along an arbitrary rotated `g` must produce the correct `a_up`.
3. **Filter** (`dsp/filters.py`): 2nd-order Butterworth **band-pass 0.5–5 Hz** using `scipy.signal.butter(..., output='sos')` with streaming `sosfilt` and persistent `zi`. Reset state on a discontinuity.
4. **Compression detection** (`dsp/compressions.py`):
   - Keep a rolling buffer of the last 4 s of filtered `a_up`.
   - Every packet, run `find_peaks` on `a_up` (bottom of a compression = maximum upward acceleration) and on `-a_up` (top of a compression). Use:
     - `distance = 0.3 s × fs` (caps the rate at 200 cpm)
     - `prominence ≥ 3.0 m/s²` (tune with real data; make it a config value)
   - Only **commit** a peak once it's at least 0.25 s old (so it's stable) and more than 0.3 s after the last committed peak of the same type.
   - Each committed **bottom** peak becomes a `Compression` event: `{t, interval_s (from previous), inst_rate_cpm = 60/interval}`.
   - `rate_cpm` = 60 / median(last 5 intervals). Ignore intervals over 2 s, since those are pauses.
5. **Depth** (`dsp/depth.py`), per cycle, using the segment between two consecutive **top** troughs (t₀ to t₁):
   - Take the raw (not band-passed) `a_up` in that segment and subtract its mean.
   - Integrate with cumulative trapezoid to get `v(t)`. Remove a linear trend so `v(t₀) = v(t₁) = 0` (zero-velocity assumption at the tops).
   - Integrate again to get `x(t)`. Remove a linear trend so `x(t₀) = x(t₁)`.
   - `depth_raw_cm = (max(x) − min(x)) × 100`.
   - `depth_cm = depth_raw_cm × depth_scale` (from calibration, default 1.0).
   - Attach the depth to the matching bottom-peak compression event.
   - Reject cycles under 0.25 s or over 1.5 s long, or containing a discontinuity (`depth = null`).
6. **Pause and CCF tracking** (`session.py`):
   - A pause is any gap over `pause_threshold_s` (2 s) since the last compression. Track the count, the longest pause, and total hands-off time.
   - `ccf = (session_time − hands_off_time) / session_time`.
7. **Fatigue** (`dsp/fatigue.py`):
   - `baseline_depth` = median depth of compressions between 10 s and 40 s into the current rescuer cycle (at least 10 compressions).
   - `recent_depth` = median of the last 15 compressions.
   - `depth_drop = 1 − recent/baseline`.
   - `hr_rise` = current HR − HR at cycle start.
   - `fatigue_score` = clamp(0, 1, 0.7 × clamp(depth_drop / 0.25) + 0.3 × clamp(hr_rise / 30)).
   - `swap_recommended` = true if `cycle_elapsed ≥ 120 s`, **or** if `depth_drop ≥ 0.15` holds for 10 s or more after 60 s.
   - The cycle resets when the UI sends `{"cmd":"swap"}` or after a pause of more than 5 s.
8. **Record** every raw packet, heart rate message and compression event to `data/sessions/<session_id>/stream.jsonl`, with laptop receive time.
9. **Broadcast** state at 20 Hz (§7.3).

**Unit tests (required, use synthetic signals):**

- Synthetic displacement `x(t) = D/2 · (1 − cos 2πft)`, so `a(t) = D/2 · (2πf)² · cos 2πft`. Test with f = 110/60 Hz and D = 5.5 cm, sample at 100 Hz, and add Gaussian noise (σ = 0.3 m/s²).
  - Rate within ±2 cpm. Depth (scale 1.0) within ±0.5 cm. Compression count within ±1 over 30 s.
- Rate sweep from 80 to 140 cpm, all detected within ±3.
- A 3 s pause in the middle is detected as one pause, and CCF is computed correctly.
- Fatigue: depth decays linearly from 5.5 to 4.2 cm over 120 s, so `swap_recommended` fires before 120 s.
- Packet gap: dropping one batch doesn't crash anything and doesn't produce a bogus depth.
- Scoring math (§8.5).

### 6.4 Watch simulator (`backend/tools/sim_watch.py`)

This is critical for development and for a backup demo.

- It connects to `ws://localhost:8000/ingest` and sends **exactly** the same binary packets as the phone (header `0x01` plus the CPR1 packet), at real time, 20 samples every 200 ms.
- It generates `ua` from the synthetic model above. It applies a random constant device orientation by rotating both `ua` and `g` with a random rotation matrix, so it exercises the gravity projection.
- CLI flags:
  `--rate 110 --depth 5.5 --noise 0.3 --duration 180 --fatigue 0.25 --pause-at 45:3 --hr-start 85 --hr-end 125 --drop-rate 0.01 --scenario good|shallow|fast|slow|fatigue|chaotic`
- Interactive mode (`--interactive`): keys change things live. `+`/`-` changes rate, `[`/`]` changes depth, and `p` toggles a pause. Use this to rehearse the coach voice lines.

### 6.5 Web dashboard (Vite, React, TypeScript)

**Layout:** full screen, dark theme, readable from 3 m away. Designed for 1440×900 and up; it must also look fine on a projector at 1920×1080.

```
┌────────────────────────────────────────────────────────────────────────────────┐
│ CPR COACH            [● Watch] [● Phone] [● Camera]    ⏱ 01:23   cycle 01:23   │
├─────────────────────────────┬──────────────────────────────────────────────────┤
│                             │   RATE                 DEPTH                     │
│   CAMERA VIEW               │   ┌─────────┐         ┌───┐ 6.0 ─              │
│   (video + skeleton         │   │  112    │         │███│  ← green band 5–6  │
│    overlay; elbow angle     │   │  /min   │         │███│ 5.0 ─              │
│    label on elbow)          │   └─────────┘         └───┘  5.4 cm            │
│                             │   arc gauge 80–140,    vertical bar 0–8 cm     │
│                             │   green zone 100–120                            │
├─────────────────────────────┴──────────────────────────────────────────────────┤
│ WAVEFORM: scrolling 6 s of displacement-ish trace, compression ticks, depth labels│
├────────────────────────────────────────────────────────────────────────────────┤
│ ✅ Elbows locked   ✅ Shoulders over hands   ⚠️ Full recoil   ❤️ 104 bpm  Fatigue ▓▓░░ │
├────────────────────────────────────────────────────────────────────────────────┤
│                    🗣  "PUSH HARDER"   (big coach banner, color-coded)          │
└────────────────────────────────────────────────────────────────────────────────┘
```

**Screens and modes:**

1. **Home**: name input ("Who's doing CPR?"), a Start button, a Calibrate button, and the Leaderboard.
2. **Calibration wizard** (§8.6).
3. **Live session** (above). A countdown of "3… 2… 1… Start compressions" starts the metronome.
4. **Summary**: score out of 100 with a letter grade, then rate %, depth %, CCF, elbow lock %, alignment %, pauses, a depth-over-time chart with the green band, and the moment fatigue was detected. Buttons: "Add to leaderboard" and "Try again".
5. **Leaderboard**: top 10 with name, score and a date stamp.

**Keyboard shortcuts** (for the demo operator): `Space` start/stop, `S` swap rescuer, `M` mute voice, `B` toggle metronome, `C` camera on/off, `D` debug overlay (raw signals, fps, packet rate, gaps), `F` fullscreen.

**Camera, `pose/poseLandmarker.ts`:**

- `PoseLandmarker.createFromOptions` with `runningMode: "VIDEO"`, `numPoses: 1`, a **local** model path `/models/pose_landmarker_full.task`, and `delegate: "GPU"` with a CPU fallback.
- `getUserMedia({video: {width: 1280, height: 720}})`. Call `detectForVideo(video, performance.now())` in a `requestAnimationFrame` loop and skip frames if the previous call hasn't finished.
- Use pixel coordinates for all angles: multiply normalized x by video width and y by video height before doing geometry.

**Posture metrics, `pose/postureMetrics.ts`:**

- Landmarks: shoulders 11/12, elbows 13/14, wrists 15/16, hips 23/24.
- **Side selection:** use the side (left or right) with the higher mean `visibility` over shoulder, elbow and wrist. This works well with a side camera view.
- **Elbow angle** = angle at the elbow between the shoulder and the wrist. Smooth with an EMA (α = 0.3). `elbowsLocked = angle ≥ 160°`. Count it as a violation only if it holds for at least 0.5 s.
- **Shoulders over hands:** the angle of the shoulder→wrist vector from vertical. `aligned = angle ≤ 15°`.
- **Wrist-y signal:** wrist y in pixels, smoothed, used for camera compressions and recoil.
- **Recoil (camera-based):** track the rolling "top" wrist-y level over the last 10 s (95th percentile of height). If the top of each compression stays more than 15% of the compression amplitude below that level for 3 or more consecutive compressions, set `incompleteRecoil = true`. This is a heuristic; label it "beta" in debug mode.

**Camera compressions fallback, `pose/cameraCompressions.ts`:**

- Run the same peak logic on the wrist-y signal (simple local extrema with a minimum distance of 0.3 s and minimum prominence of 1.5% of frame height).
- `rate_cpm` works the same way. `depth_cm_est = amplitude_px × cm_per_px`, using `cm_per_px` from calibration. Mark it as an estimate in the UI (show "~").

**Fusion, `fusion/fuse.ts`:**

- Rate: from the watch if the watch has been connected with a compression in the last 3 s; otherwise from the camera. Show the source as a small label ("via watch" or "via camera").
- Depth: from the watch if available (calibrated). Otherwise the camera estimate with "~".
- Posture and recoil: camera only. If the camera is off, show "—".
- Output one `LiveState` object that every component and the coach engine read from.

**Metronome, `audio/metronome.ts`:**

- Use WebAudio with look-ahead scheduling (the Chris Wilson "A Tale of Two Clocks" pattern): schedule `OscillatorNode` clicks 100 ms ahead using `audioContext.currentTime`. Accent every 30th beat, since 30 compressions is one cycle in the 30:2 ratio; this is optional.
- Default 110 BPM, toggled with `B`. It also sends `{"cmd":"metronome","on":..,"bpm":110}` through the backend to the watch.

**Speech, `coach/speech.ts`:**

- `speechSynthesis` with a pre-chosen English voice, rate 1.1. Cancel any in-progress utterance before a higher-priority one. Provide a mute toggle.

---

## 7. Message schemas

### 7.1 Phone → backend (`/ingest`)

- Binary: `0x01` followed by the CPR1 IMU packet (§6.1).
- Text:
  - `{"t":"hello","device":"iphone"|"sim"|"replay","app_version":"0.1"}`
  - `{"t":"hr","bpm":104,"ts":<watch ts>,"phone_rx":<unix s>}`
  - `{"t":"status","watch_reachable":true,"drops":3}`, sent every 2 s

### 7.2 Backend → phone (`/ingest`, text)

- `{"cmd":"start"}`, `{"cmd":"stop"}`, `{"cmd":"metronome","on":true,"bpm":110}`

### 7.3 Backend → dashboard (`/ws`)

`state`, sent at 20 Hz:

```json
{
  "type": "state",
  "ts": 1729790000.123,
  "session": {"id": "2026-10-24T15-02-11", "status": "idle|running|summary", "elapsed_s": 83.2, "cycle_elapsed_s": 83.2, "name": "Judge Alice"},
  "sources": {"phone_connected": true, "watch_streaming": true, "packet_rate_hz": 5.0, "gaps": 0, "last_packet_age_ms": 140, "source": "watch|sim|replay|none"},
  "hr": {"bpm": 104, "age_s": 3.1},
  "compressions": {"count": 147, "rate_cpm": 112.4, "last_depth_cm": 5.4, "depth_avg5_cm": 5.3, "last_t": 1729790000.01},
  "pauses": {"count": 1, "longest_s": 3.2, "hands_off_s": 3.2, "ccf": 0.96, "in_pause": false, "pause_elapsed_s": 0},
  "fatigue": {"score": 0.21, "baseline_depth_cm": 5.6, "recent_depth_cm": 5.2, "swap_recommended": false},
  "wave": {"t0": 1729789994.1, "fs": 50, "a_up": [/* last 6 s, decimated to 50 Hz */]}
}
```

`compression` event (sent immediately on each detection):

```json
{"type": "compression", "t": 1729790000.01, "interval_s": 0.54, "inst_rate_cpm": 111.1, "depth_cm": 5.4, "rate_ok": true, "depth_ok": true}
```

### 7.4 Dashboard → backend (`/ws`)

`{"cmd":"start","name":"Judge Alice"}`, `{"cmd":"stop"}`, `{"cmd":"swap"}`, `{"cmd":"metronome","on":true,"bpm":110}`

---

## 8. Product logic

### 8.1 Session state machine

`idle → countdown (3 s) → running → summary → idle`

- `running` begins when the countdown ends. The session clock starts at the **first compression** or 5 s after the countdown, whichever comes first, so a slow start isn't penalized too harshly.
- Auto-stop isn't required. The operator presses Space.

### 8.2 Per-compression grading

- `rate_ok` = instantaneous rate between 100 and 120.
- `depth_ok` = depth between 5.0 and 6.0 cm (when depth is available).
- `too_shallow` = depth below 5.0. `too_deep` = depth above 6.0.

### 8.3 Rolling windows used by the coach

- Rate: median of the last 5 intervals.
- Depth: median of the last 5 depths.
- Posture: fraction of the last 2 s with a violation, which must be 60% or more to count.

### 8.4 Coach rule table

Evaluate rules every 250 ms. Pick the **highest-priority** active rule that isn't in cooldown. Global minimum gap between spoken prompts is **3 s**. Per-rule cooldown is **8 s**.

| Priority | Rule ID | Condition | Spoken line | Banner color |
|---|---|---|---|---|
| 1 | `no_compressions` | running and no compression for 2 s or more | "Keep pushing! Don't stop." | red |
| 2 | `swap` | `fatigue.swap_recommended` | "Switch rescuers now." | purple |
| 3 | `too_shallow` | depth median below 5.0 | "Push harder." | red |
| 4 | `too_slow` | rate below 100 | "Faster." | amber |
| 5 | `too_fast` | rate above 120 | "Slow down." | amber |
| 6 | `elbows_bent` | elbow violation | "Lock your elbows." | amber |
| 7 | `not_over_hands` | alignment violation | "Shoulders over your hands." | amber |
| 8 | `incomplete_recoil` | recoil flag | "Let the chest come all the way up." | amber |
| 9 | `too_deep` | depth median above 6.5 | "A little less force." | amber |
| 10 | `praise` | all green for 10 s or more, every 15 s at most | "Great compressions, keep going." | green |

- The first 5 s of running produce only `praise` or `no_compressions`. That gives the person time to get going.
- The banner shows the current top issue even while the voice is in cooldown.

### 8.5 Scoring (summary)

```
rate_pct     = % of compressions with rate_ok
depth_pct    = % of compressions with depth_ok (if no depth data: reweight, excluding this term)
ccf          = chest compression fraction (0–1)
elbow_pct    = % of running time with elbows locked (camera)
align_pct    = % of running time aligned (camera)

score = 30*rate_pct + 30*depth_pct + 20*min(ccf/0.80, 1) + 10*elbow_pct + 10*align_pct
```

Normalize the weights over whichever terms are available. Letter grades: A ≥ 90, B ≥ 80, C ≥ 70, D ≥ 60, otherwise F. Unit test the reweighting.

### 8.6 Calibration wizard (about 60 s, do it before demos)

1. **Camera framing:** "Kneel beside the cushion. Your full upper body should be in view." The skeleton overlay goes green when shoulder, elbow and wrist on one side all have visibility above 0.6.
2. **Depth calibration (watch):** "Do 10 compressions that press the cushion down exactly 5 cm. Use the ruler." Then `depth_scale = 5.0 / median(depth_raw_cm)`. Clamp it between 0.5 and 2.0; outside that range, warn "calibration looks off, try again". POST it to `/api/calibration`.
3. **Camera scale:** use the same 10 compressions. `cm_per_px = 5.0 / median(wrist amplitude_px)`.
4. Show the resulting accuracy: "Watch depth check: 5.1 ± 0.3 cm".

---

## 9. Hands-on setup steps (detailed in `apple/SETUP.md`)

### 9.1 Xcode project

1. Xcode → File → New → Project → **watchOS → App**. Product name `CPRCoach`, choose **"Watch App with New Companion iOS App"**, SwiftUI, Swift.
2. Save it into `cpr-coach/apple/CPRCoach/`.
3. Set the watch target's **Minimum Deployment to watchOS 10.0**, because a Series 5 can't run watchOS 11. Confirm your installed Xcode can still target watchOS 10; if it can't, use an older Xcode.
4. Signing: select your Personal Team (a free Apple ID works) for **both** targets. Give them unique bundle IDs, such as `com.<you>.cprcoach` and `com.<you>.cprcoach.watchkitapp`.
5. Watch target → Signing & Capabilities → add **HealthKit** and **Background Modes → Workout processing**.
6. iOS target → add **HealthKit**.
7. Add the Info.plist keys listed in §6.1 and §6.2.
8. Replace the generated Swift files with the project's own sources (`apple/install-sources.sh`).

### 9.2 Devices

1. iPhone: Settings → Privacy & Security → **Developer Mode** on, then restart.
2. Watch: Settings → Privacy & Security → **Developer Mode** on. You may need to install a build first for the option to appear.
3. Connect the iPhone by cable. Keep the watch on its charger, near the phone, and unlocked.
4. Run the iOS scheme first, then the watch scheme. **The first watch install can take 5–15 minutes.** Do this in the first hour, not the last.
5. With a free account, trust the developer on the phone: Settings → General → VPN & Device Management.

### 9.3 Laptop

```bash
cd backend && python3 -m venv .venv && source .venv/bin/activate && pip install -r requirements.txt
cd ../web && npm install && mkdir -p public/models && curl -L -o public/models/pose_landmarker_full.task \
  https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_full/float16/latest/pose_landmarker_full.task
make dev   # runs uvicorn on 0.0.0.0:8000 and vite on 5173 (proxy /ws, /api to 8000)
ipconfig getifaddr en0   # laptop IP to type into the iPhone app
```

### 9.4 Network checklist

- Start the simulator from **another machine or the phone** to test reachability. Or, on the laptop: `python -c "import socket;print(socket.gethostbyname(socket.gethostname()))"` and then check with the phone's relay app.
- If the phone can't connect: turn on the iPhone **Personal Hotspot** and connect the laptop to it. The laptop gets an IP like `172.20.10.x`; enter that in the relay app.
- Allow incoming connections for Python in the macOS firewall prompt.

---

## 10. Non-functional requirements

| Requirement | Target |
|---|---|
| End-to-end latency (compression to dashboard update) | ≤ 400 ms p95 |
| Dashboard frame rate | ≥ 30 fps, with pose inference at ≥ 15 fps |
| Backend CPU | < 25% of one core |
| Startup time | `make dev` to dashboard ready in under 10 s |
| Offline | Works with **no internet**: models are local, no CDN fonts, no cloud APIs |
| Robustness | Any source can disconnect and reconnect mid-session without a crash; the UI shows it |
| Privacy | No video is recorded or transmitted. Only numeric data is stored locally. |

---

## 11. Demo script (3 minutes)

1. **Hook (20 s):** "Raise your hand if you're CPR certified. Now, would you know if you were doing it right? Studies show most bystanders push too shallow and too slow, and quality falls apart within about 2 minutes from fatigue." (Check the exact statistics before pitching.)
2. **Live run, teammate (60 s):** the watch is on the wrist, the camera has a side view, and the dashboard is on the projector. The teammate deliberately goes shallow and the coach says "Push harder"; they correct. They bend their elbows and the coach says "Lock your elbows"; they correct. The metronome is audible and the watch taps the beat.
3. **Fatigue moment (20 s):** "After 2 minutes, depth drops without you noticing. CPR Coach catches it." Trigger it with the swap logic, or show the replay of a pre-recorded fatigue session using `replay.py`.
4. **Judge participation (60 s):** a judge does 30 seconds of CPR, gets a score, and goes on the leaderboard.
5. **Tech (20 s):** "100 Hz IMU data projected onto gravity, per-cycle double integration with zero-velocity resets, MediaPipe pose for form, all fused on-device with no cloud."
6. **Close:** "Every smartwatch could be a CPR instructor. Next steps: 911 dispatcher integration and auto-launch on the watch."

**Backup plan:** if the watch fails live, press a key to switch to camera-only mode, which still shows rate, estimated depth and posture. If everything fails, run `replay.py` on a recorded good session with a pre-recorded screen capture.

---

## 12. Build order and milestones (follow exactly)

> Times assume roughly 20 hours of build time. Scale them proportionally. **Each milestone must end in a working, demoable state.**

### M0: Scaffolding (0.5 h)

- Repo layout (§5), Makefile, `targets.json`, backend health route, Vite app showing "CPR Coach" plus status pills.
- **Done when** `make dev` serves the dashboard and `/api/health` returns OK.

### M1: Camera-only MVP, no Apple hardware (3 h)

- Webcam, PoseLandmarker, skeleton overlay, elbow angle, alignment, wrist-y camera compressions (rate plus relative depth).
- Fusion (camera only), metronome, the coach engine with the rule table, speech, RateGauge, DepthBar (showing "~"), PostureChecklist, CoachBanner.
- **Done when** a person doing compressions on a cushion in front of the laptop gets a live rate and spoken coaching.

### M2: Backend DSP and simulator (3 h)

- Packet decode, vertical projection, filters, compression detection, depth, pause and CCF tracking, broadcaster. `sim_watch.py` with scenarios. **All unit tests in §6.3 pass.**
- Fusion prefers the watch source, and the waveform renders.
- **Done when** `make sim SCENARIO=shallow` makes the dashboard say "Push harder", and `make test` is green.

### M3: Apple pipeline (4 h; start the human Xcode steps in parallel during M1)

- Watch app (workout, motion, batching, heart rate, haptic metronome), iOS relay, `/ingest` binary handling, command round trip.
- **Done when** real compressions with the watch on show live rate and depth on the dashboard, with gaps at 1% or less over 2 minutes.

### M4: Calibration, fatigue, session, summary, leaderboard (3 h)

- Calibration wizard, fatigue model and swap prompt, session state machine, scoring, summary screen, leaderboard persistence, recorder and `replay.py`.
- **Done when** a full session (start, 2 minutes, swap prompt, stop, summary, leaderboard) works end to end, and a recorded session can be replayed.

### M5: Polish and demo hardening (3 h)

- Projector-friendly visuals, smooth animations on the gauges, countdown, debug overlay, keyboard shortcuts, a "Training tool – not a medical device" footer, and README.
- Record 2 golden sessions (good and fatigue) for backup replay.
- Run the full demo script (§11) 3 times.

### Stretch (only if M0–M5 are done)

- **S1:** Dispatcher mode, a big-text minimal UI for a phone browser.
- **S2:** Watch-only mode, showing rate and depth on the watch face with haptic "push harder" patterns (double tap).
- **S3:** 30:2 mode, which counts 30 compressions and then prompts "Give 2 rescue breaths" with a 10 s pause allowance.
- **S4:** A team view that compares two rescuers' fatigue curves on the summary.

---

## 13. Acceptance test checklist

- [ ] `make test` passes, including all synthetic DSP tests.
- [ ] Simulator scenarios `good`, `shallow`, `fast`, `slow`, `fatigue` and `chaotic` each trigger the expected coach line within 5 s.
- [ ] With the real watch at a steady metronome of 110, the displayed rate is between 107 and 113.
- [ ] After calibration, 10 ruler-verified 5 cm compressions read 5.0 ± 1.0 cm.
- [ ] Bending the elbows triggers "Lock your elbows" within 2 s.
- [ ] Stopping for 3 s triggers "Keep pushing" and counts a pause.
- [ ] Pulling the phone's Wi-Fi mid-session switches to the camera source, with no crash, and switches back on reconnect.
- [ ] The summary score matches the formula (unit tested).
- [ ] The leaderboard persists across a backend restart.
- [ ] The whole system works with the laptop's internet turned off.

---

## 14. Risks and mitigations

| Risk | Mitigation |
|---|---|
| The first watch deploy is slow or fails | Start in hour 1, in parallel with M1. The camera-only MVP is still a full demo. |
| Hackathon Wi-Fi blocks phone-to-laptop traffic | Use the iPhone Personal Hotspot (§9.4). |
| Haptic metronome drops beats at 110 BPM | Tap every other beat. The audio metronome is primary. |
| Depth drift or wrong scale | Per-cycle zero-velocity detrending plus ruler calibration. Show depth with one decimal and a green band, not false precision. |
| Pose struggles with lighting or clothing | Side view, good lighting, contrasting clothes. The debug overlay shows visibility scores. |
| WatchConnectivity latency spikes | Batching keeps the message rate low. Depth is computed per cycle, so a few hundred ms of latency is fine. The metronome runs locally on each device. |
| Judges ask "is this accurate?" | Show the ruler calibration live, plus the unit-test results on synthetic signals. |

---

## 15. Coding standards

- Python: type hints, `ruff`-clean, with pure DSP functions separated from I/O so they can be tested.
- TypeScript: `strict: true`, no `any` in fusion and coach code. All thresholds come from `targets.json` or a `config.ts`, never magic numbers inline.
- Swift: small focused types, `@MainActor` for UI state, with motion handling on a background queue.
- Every module has a short header comment explaining its role in the pipeline.
- README sections: Setup, Run (sim / real), Calibrate, Demo, Troubleshooting.
