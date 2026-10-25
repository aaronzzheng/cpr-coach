# CPR Coach: project inventory

Everything about CPR Coach in one place, for judging Q&A, interviews and résumé talk. Every number here matches the code or our tests; simulated results are labelled as simulated.

- **Event:** HackOHI/O 2026, October 24–25, 2026
- **Team:** Aaron Zheng, Jaeha Lee, Eason Zheng. Fill in who built what before an interview (see section 13).
- **Repo:** https://github.com/aaronzzheng/cpr-coach (private unless you change it)
- **Demo video:** https://youtu.be/oubjYkOBK_0
- **Slides:** `~/Downloads/CPR Coach Video Slides/` (8 PNGs and a PDF)
- **Video script:** `demo/VIDEO_SCRIPT.md`

---

## 1. Pitches

**10 seconds:**
CPR Coach turns your iPhone and Apple Watch into a real-time CPR coach that measures every compression and talks you through it.

**30 seconds:**
Only about four in ten people who have a cardiac arrest outside a hospital get CPR from a bystander, and those who help get no feedback. CPR Coach uses the Apple Watch on the pushing wrist to feel every compression, and the iPhone's camera to watch your form. A Kalman filter fuses the two into real depth in centimetres. It coaches you out loud, hands-free, in seven languages, and it creates a report for paramedics at the end.

**2 minutes (for "tell me about a project"):**
1. **Problem:** 263,000 EMS-treated cardiac arrests a year in the US, only about 40% get bystander CPR, and existing tools are either training-only, extra hardware, or can't see you.
2. **Idea:** two devices people already own. The watch feels each push; the phone sees the body.
3. **Hardest technical part:** depth. The watch drifts, and the camera has no scale. We built an extended Kalman filter that fuses them and lets the camera calibrate itself from the watch. Then a 40 ms clock gap caused a 10% error, which we fixed with cross-correlation.
4. **Result:** a working iPhone and Apple Watch app with voice coaching, fatigue prediction, an AED guide and a paramedic report, plus a web version. Simulated depth error is about 0.2 cm.
5. **Next:** validation on a training manikin.

---

## 2. Key numbers to know cold

| Number | What it is | Source |
|---|---|---|
| 263,000 | US out-of-hospital cardiac arrests per year treated by EMS (about 356,000 total) | CARES registry / AHA |
| ~4 in 10 | get CPR from a bystander | AHA, CARES |
| up to 10% | drop in survival per minute without CPR | AHA |
| ~7 in 10 | of these arrests happen at home | AHA |
| 240 | participants in the manikin study where a phone app didn't improve effective compressions | *Resuscitation*, 2014 |
| 5–6 cm, 100–120/min | AHA adult depth and rate targets | AHA guidelines |
| 100 Hz | watch motion sampling rate | `MotionStreamer.swift` |
| 20 samples / 200 ms | per watch packet | `MotionStreamer.swift` |
| 30 fps | camera rate for pose | `CameraPose.swift` |
| 0.2 cm | simulated fused depth error | our simulated tests |
| ±1 /min | simulated rate error (90% of 36 sessions) | our simulated tests |
| 2–9 cm → 0.2 cm | camera-only depth spread → fused error | challenge 1 |
| 40 ms → 10% error → ±1% | clock gap fix | challenge 2 |
| 6 → 0 in 100 | fatigue false alarms before → after | challenge 3 |
| 56 / 36 | backend / web automated tests | `pytest`, `vitest` |
| 7 | languages: English, Spanish, French, Chinese, Korean, Japanese, Hindi | `L10n.swift` |
| 40 | commits, about 15 hours, Oct 24 10:58 → Oct 25 01:49 | git log |

---

## 3. The problem and research

- Cardiac arrest outside a hospital is common (about 356,000 a year in the US, 263,000 treated by EMS), and survival depends on immediate good CPR.
- Bystander CPR happens in only about 40% of cases, and untrained helpers tend to push too shallow and too slow, and tire within about 2 minutes without noticing.
- **What exists:**
  - **CPR classes:** teach and measure, but only in class. Skills fade within months.
  - **Feedback devices** (for example, Laerdal CPRmeter): a puck under your hands. Bought for trained responders; one sensor can misread depth on soft surfaces.
  - **Phone-on-chest apps** (for example, PocketCPR): in a 240-person manikin study (*Resuscitation* 2014), the phone app didn't improve effective compressions compared with no feedback.
  - **911 dispatcher-assisted CPR:** live, but the dispatcher can't see or measure anything.
- **Our gap:** nothing helps in a real emergency while both checking your form and measuring depth, using hardware you already own.

---

## 4. What the app does (feature inventory)

**Emergency flow (iPhone):**
1. Start: tap "Someone collapsed?", say "Hey Siri, start CPR with CPR Coach", or use the Action button.
2. Spoken check: "Tap their shoulders and shout. Are they responding? Say yes or no." Then "Are they breathing normally? Gasping doesn't count." Big Yes/No buttons as a fallback.
3. If not breathing: a **simulated** emergency call (a green call pill with a timer; it never dials) and a 110 BPM metronome.
4. Live coaching on rate, depth, elbows, alignment, hand placement, recoil, and fatigue.
5. Every 2 minutes: "Switch rescuers if someone can take over." After an AED arrives: "Let the AED analyze."
6. AED button: a pad placement guide; it logs when the AED arrived.
7. "Stop": a **paramedic report** with a timeline (collapse found, help called, compressions started, rescuer swaps, AED arrived, stopped), CPR quality, and a QR code.

**Coaching cues (spoken and on screen):** "Give 2 breaths", "Keep pushing! Don't stop.", "Switch rescuers now.", "You're tiring. Get ready to switch rescuers.", "Push harder.", "Faster.", "Slow down.", hand position up or down, "Let the chest come all the way up.", "Lock your elbows.", "Shoulders over your hands.", "A little less force.", "Great compressions, keep going."

**Voice commands (7 languages):**
- "How am I doing?": reads back rate and depth
- "How long?": time and number of compressions
- "Swap" / "Switch"
- "Call for help"
- "Stop"
- "Yes" / "No": during the emergency check
- "Done": after rescue breaths

**Other modes and features:**
- **Patient profiles:** adult 5–6 cm, child 4.5–5.5 cm, infant 3.5–4.5 cm; the same 100–120/min rate. "Too deep" is 6.5, 6.0 and 5.0 cm respectively.
- **30:2 mode:** 30 compressions, then a prompt for 2 rescue breaths; "Done" resumes.
- **Practice mode** with an **AI debrief** afterwards (Apple's on-device language model).
- **Skills check:** a 2-minute pass/fail test for classes.
- **Live Activity:** the instruction, rate and depth on the lock screen.
- **Siri and App Shortcuts:** "Start CPR with CPR Coach", "CPR Coach emergency", "Someone collapsed, open CPR Coach", "Practice CPR with CPR Coach".
- **Watch app:** streams motion; gives wrist taps for cues and a haptic metronome; can coach on its own and speak its cues when started from the watch.
- **Demo replay:** long-pressing "Watch" in the top bar cycles through recorded sessions (good, then tiring rescuer). This was used for filming the fatigue warning.
- **Web version:** a React dashboard with the same coaching, MediaPipe pose, voice commands, languages, patient targets, 30:2, skills check, paramedic report, calibration wizard, scorecard and leaderboard.

---

## 5. Architecture

**How it evolved, which is a good story:**
1. **The original plan (PRD), v1:** watch → iPhone (only a relay) → laptop over WebSocket. A Python backend did the signal processing, and a React dashboard on the laptop used the webcam. Milestone 1 had to work with **no Apple hardware at all** (camera-only), and a watch **simulator** let us build without the watch.
2. **About 16:00 on day 1:** we moved everything onto the phone. The Python signal pipeline and the web coaching logic were **ported to Swift** (`WatchDSP.swift`, `CoachLogic.swift`), so the iPhone app works standalone: camera plus watch, no laptop.
3. **The laptop dashboard still exists** as the web version (`web/` + `backend/`).

**On-phone data flow:**
```
Apple Watch (Core Motion 100 Hz)
   └─ CPR1 packets (20 samples, every 200 ms) over WatchConnectivity
        └─ Watch pipeline: gravity projection → band-pass 0.5–5 Hz → peak detection → per-cycle depth → fatigue
iPhone front camera (30 fps, widest 4:3, Center Stage off)
   └─ Apple Vision 2D + 3D body pose → elbow angle, alignment, hand placement, recoil, wrist height
Watch motion + camera wrist height
   └─ Clock sync (cross-correlation) → Extended Kalman filter → depth in cm + learned camera scale
All of the above → coaching engine (rules, priorities, cooldowns) → voice (AVSpeechSynthesizer) + watch haptics + UI
Microphone → on-device speech recognition → command matcher → actions
```

**The CPR1 packet format** (shared by the Swift watch and the Python backend):
- **Header:** 12 bytes, little-endian. Magic number `CPR1` (u32), sequence number (u32), count (u16), reserved (u16).
- **Each row:** 44 bytes. A timestamp (f64), then 9 × f32: user acceleration xyz in g, gravity xyz in g, rotation rate xyz in rad/s.
- One packet holds 20 rows, so it's 12 + 20 × 44 = 892 bytes.
- **Gaps:** a sequence tracker counts dropped batches. When the phone isn't reachable, the watch drops batches instead of queueing them, which avoids stale bursts.

---

## 6. How each part works

### 6.1 Watch sensing (`apple/Sources/Watch/`, `apple/Sources/Core/WatchDSP.swift`)
- **Staying awake:** an `HKWorkoutSession` (HealthKit) keeps the app running with the screen off.
- **Sampling:** `CMMotionManager` deviceMotion at 100 Hz on a background queue, batched into 20-sample packets.
- **Vertical acceleration:** user acceleration is projected onto the gravity vector, which gives up-and-down motion no matter how the watch sits on the wrist.
- **Filtering:** a band-pass filter at 0.5–5 Hz (2nd-order biquad cascade, the same as `scipy.signal.sosfilt`) keeps CPR frequencies and removes drift and jitter.
- **Peak detection:** an online version of `scipy.signal.find_peaks`, with peaks at least 0.3 s apart and a prominence of 3.0 m/s². Bottoms and tops give the **rate** and **count**.
- **Depth:** per-cycle double integration of acceleration from top to bottom to top, with linear detrending. Each cycle starts fresh, so errors can't build up.
- **Clock:** the watch and phone clocks differ, so outputs are mapped to the phone clock through a rolling-minimum offset.

### 6.2 Camera and computer vision (`CameraPose.swift`, `CoachLogic.swift`)
- **Camera:** the front camera at its widest view (full 4:3 sensor, minimum zoom, Center Stage off), 30 fps, so a phone on the floor sees the whole upper body.
- **Models:** Apple Vision `VNDetectHumanBodyPoseRequest` (2D joints) plus `VNDetectHumanBodyPose3DRequest` (3D joints). These are pretrained on-device models; **we didn't train our own**.
- **Elbow angle:** from shoulder, elbow and wrist, smoothed (EMA, alpha 0.3). 160° or more counts as locked. The 3D pose gives the true angle. Without 3D, there's +8° of slack, because perspective can only make a straight arm look bent.
- **Confidence:** joints below 0.3 confidence are ignored.
- **Alignment:** the angle of the shoulder-to-wrist line from vertical.
- **Hand placement:** Vision also finds the patient (a second, lying-down body). The hands' position along the torso runs from 0 (shoulders) to 1 (hips); the target is about 0.2–0.45 (lower half of the breastbone). It only flags a problem after it lasts a couple of seconds.
- **Recoil (leaning):** a high percentile of the stroke tops marks the chest at rest. A stroke stopping more than 1 cm short on half of the last 8 compressions means leaning. The camera scale from the fusion turns pixels into cm.
- **Camera-only compressions:** a zig-zag detector on wrist height gives the rate when there's no watch.

### 6.3 Depth fusion: the extended Kalman filter (`DepthFusion.swift`)
- **Why:** the watch is precise but drifts when integrated twice. The camera never drifts, but it measures pixels with an unknown scale.
- **State `[p, v, s, b]`:** `p` is wrist height in metres, `v` is velocity, `s` is camera pixels per metre, `b` is the camera offset in pixels.
- **Predict:** the watch's vertical acceleration drives `p` and `v`. Process noise is 0.4 m/s². `s` and `b` slowly random-walk (2 px/m per √s and 6 px per √s).
- **Update:** each camera frame measures wrist height in pixels, y = b − s·p, with 6 px noise (landmark jitter). The measurement is nonlinear in `s` and `p`, hence an *extended* Kalman filter.
- **Bias:** a high-pass filter with τ = 2 s removes accelerometer bias, with only about 3° of phase lag at CPR rates.
- **Result:** drift-free depth in cm. The camera learns its scale from the watch, so if the watch drops out, camera depth stays metric.
- **Tuning:** noise parameters were tuned on synthetic data.

### 6.4 Clock synchronisation (cross-correlation)
- **Problem:** Bluetooth latency and camera processing put the two streams tens of milliseconds apart. 40 ms caused a 10% depth error.
- **Fix:** on a side view, the camera's wrist height moves in step with the watch's upward acceleration. We cross-correlate the two signals over candidate lags and take the lag with the best match as the clock offset. Depth error dropped to about ±1%.

### 6.5 Which depth to trust
- **Priority:** watch + camera fused > watch alone > camera with the scale learned from the watch > camera from arm length (an uncalibrated estimate, shown as "≈").
- **Safety rule:** the uncalibrated camera estimate is displayed but **never triggers** "Push harder" or "A little less force".
- **Tolerance:** depth within ±0.3 cm of the target band counts as on target. That's about our measurement error, and it made hitting the target less frustrating.

### 6.6 Coaching engine (`CoachLogic.swift`, `web/src/coach/`)
- **Evaluation:** every 0.25 s. The highest-priority active rule sets the banner.
- **Priority order:**
  1. breaths
  2. no compressions
  3. switch now
  4. too shallow / switch soon
  5. too slow
  6. too fast / hands misplaced
  7. recoil
  8. elbows
  9. alignment
  10. too deep
  11. praise
- **Speaking:** at least **6 s** between spoken lines, each rule repeats at most every **15 s**, and praise at most every **30 s**. "No compressions" fires after 2 s with nothing.
- **Interrupting:** a more important line interrupts a less important one. Replies to the rescuer's questions always interrupt.
- **Session scoring** (practice): 30% rate in range, 30% depth in range, 20% compression fraction (vs 80%), 10% elbows locked, 10% shoulders over hands. Missing terms are dropped and the rest reweighted.

### 6.7 Fatigue forecast
- **Trend:** a least-squares line over the last 60 s of per-compression depths, with at least 40 points spanning at least 25 s.
- **When it warns:** only if the slope is more than **2.5 standard errors** below zero, the trend crosses the target within **40 s**, and the forecast **holds for 5 s**.
- **Why:** single compressions vary by about ±0.5 cm, so without the significance test and hold, it gave false alarms (6 in 100 simulated steady rescuers → 0).

### 6.8 Voice (`VoiceCommands.swift`, `CoachAudio.swift`)
- **Recognition:** `SFSpeechRecognizer`, on-device where the language supports it, with continuous recognition. Each task restarts after about 50 s or after a final result.
- **Understanding:** keyword matching per language, not a language model. Negatives win ("not breathing" is a no), and "don't stop" never stops.
  - In spaced languages, single words must match whole words, so "no" doesn't fire on "know".
  - Chinese and Japanese, which have no spaces, plus Korean and Hindi, match substrings.
  - "Done" only counts during rescue breaths. That fixed Korean "됐어" triggering mid-session.
- **Echo handling:** the coach talks from the same phone, so the coach's own words are stripped from what the mic hears, and recognition restarts when it finishes a line. The first version ignored everything while the coach spoke, which lost commands.
- **Talking:** `AVSpeechSynthesizer`, with priorities. The audio session is play-and-record with the speaker on and it plays through the silent switch.
- **Metronome:** a sample-accurate looping click (`AVAudioEngine`, a 30 ms 1 kHz click per beat), so there's no tempo drift.

### 6.9 AI debrief (`Debrief.swift`)
- **Facts:** rules over the session stats choose what went well, the one thing to fix next, and why it matters, so the advice is grounded in measurements.
- **Writing:** on Apple Intelligence devices, `FoundationModels` (`LanguageModelSession`, Apple's on-device LLM) turns those facts into a short spoken-style debrief in the app's language. Otherwise the rule text is shown, translated.
- **Privacy:** nothing leaves the phone.

### 6.10 Emergency report (`Handoff.swift`)
- **Timeline events:** collapse found and checked, help called, compressions started, rescuers switched, AED arrived, compressions stopped. These are the first questions EMS asks.
- **Contents:** the timeline and CPR quality, plus a QR code that holds the same report as plain text, so a paramedic can scan it.

### 6.11 Localisation
- **Translations:** `tr()` looks up strings by their English text; `Translations.swift` was generated from per-language JSON. The web has its own `web/src/i18n/translations.json`.
- **Coverage:** speech voices and command words exist for all 7 languages.

### 6.12 Web and backend
- **Web** (`web/`): React 19 + TypeScript + Vite. MediaPipe Pose Landmarker (33 landmarks) runs offline in the browser via wasm. The Web Speech API handles voice. The coaching engine, fusion, forecast and session tracking are TypeScript versions of the same logic.
- **Backend** (`backend/`): FastAPI on port 8000, WebSocket ingest from the iPhone relay, and the Python signal pipeline (NumPy, SciPy).
- **Tools:**
  - a watch **simulator** with scenarios: good, shallow, fast, slow, fatigue, chaotic
  - **record** and **replay** of real sessions
  - **validate** (accuracy trials against a click track and a fixed depth stop)
- **Commands:** `make setup`, `make dev`, `make demo`, `make test`, `make sim SCENARIO=...`, `make replay SESSION=...`, `make validate RATE=100`.

---

## 7. Tech stack (with versions)

| Area | Tools |
|---|---|
| Apple apps | Swift 6, SwiftUI, Observation, XcodeGen; iOS 17+, watchOS 10 (Apple Watch Series 5, 2019); Xcode 27 |
| Apple frameworks | Vision (2D + 3D body pose), AVFoundation (camera, audio, TTS), Core Motion, HealthKit, WatchConnectivity, Speech, FoundationModels, ActivityKit, WidgetKit, AppIntents, simd |
| Web | React 19, TypeScript 7, Vite 8, MediaPipe tasks-vision 1.1.1, Web Speech API, qrcode |
| Backend | Python 3.11+, FastAPI, NumPy, SciPy, WebSockets |
| Testing | pytest (56), vitest (36), `make swift-check` (type-checks the Swift for iOS and watchOS) |
| Install | free Apple ID provisioning, `xcrun devicectl` |

---

## 8. Challenges (use these as interview stories)

**1. Depth from a camera has no scale**
- *Situation:* the camera alone estimated depth anywhere from 2 to 9 cm.
- *Task:* real centimetres without extra hardware.
- *Action:* added the watch and built an extended Kalman filter fusing the watch's acceleration with the camera's wrist height. The camera's scale is part of the state, so it calibrates itself.
- *Result:* about 0.2 cm error in simulated tests, and camera-only depth stays metric if the watch drops out.

**2. A 40 ms clock gap**
- *Situation:* after fusion, depth was still off by about 10%.
- *Action:* traced it to timing. Bluetooth and camera latency shift the streams. Measured the offset by cross-correlating camera wrist height against watch acceleration.
- *Result:* about ±1% error.
- *Lesson:* for sensor fusion, time alignment matters as much as the math.

**3. Fatigue warning false alarms**
- *Situation:* "switch soon" fired on rescuers who weren't tired.
- *Action:* measured it on 100 simulated steady rescuers (6 false alarms). Added a significance test on the slope (2.5 standard errors) and a 5-second hold.
- *Result:* 0 in 100. It still warns before a genuinely tiring rescuer drops below 5 cm (there's an automated test for that).

**4. Straight arms read as bent**
- *Cause:* the 2D image angle shrinks when the arm isn't side-on.
- *Fix:* added Apple's 3D body pose for the true angle, plus 8° of slack when 3D isn't available.

**5. Camera couldn't see the body**
- *Cause:* a phone on the floor cut off the upper body.
- *Fix:* forced the widest 4:3 sensor format at minimum zoom, turned Center Stage off, and fixed the preview so there are no bars or crop.

**6. Voice commands lost while the coach talked**
- *Cause:* the first version ignored all speech during the coach's lines and for 1.2 s after, and replies were dropped if the coach was mid-sentence.
- *Fix:* strip the coach's own words instead, restart recognition at the end of each line, let replies interrupt, and space cues 6 s apart instead of 3.

**7. Hardware and accounts**
- With a free Apple ID (no paid developer account), we side-loaded the watch app onto a 2019 Series 5 limited to watchOS 10.
- The watch didn't update on reinstall until we bumped the build number.

**8. Korean "됐어" ("done")** triggered mid-session. "Done" now only counts during rescue breaths.

**9. Hackathon Wi-Fi blocked device-to-device traffic** (the laptop version). The fix was the iPhone Personal Hotspot. Later the standalone phone app removed the laptop entirely.

**10. Safety decision:** the emergency call is **simulated**. It shows a call banner instead of dialing, so a demo or test can never call 911 by accident.

---

## 9. Testing, accuracy and honest limitations

**How we tested:**
- 56 backend tests:
  - rate sweep from 80 to 140/min within ±3
  - depth within 0.5 cm under noise
  - dropped packets
  - clock offset relearning
  - packet round trips
  - one test that compiles the Swift packet encoder and checks the Python decoder byte for byte
- 36 web tests: coaching rules and cooldowns, posture metrics, camera compressions, fusion, fatigue forecast, session tracking, voice matching, calibration.
- A synthetic watch simulator, plus recorded real sessions replayed through the pipeline.
- `make validate` for real accuracy trials against a click track (rate) and a fixed 5 cm stop (depth).
- Real device runs on an iPhone and an Apple Watch Series 5, on a pillow and a teammate (no real compressions on a person).

**Accuracy (simulated):** depth about ±0.2 cm; rate about ±1/min in 90% of 36 sessions (mean error 0.5/min).

**Limitations, which you should say openly:**
- No validation on a real manikin with ground-truth depth yet.
- On a soft surface such as a bed, the watch measures hand travel, which includes the mattress, so depth reads high. Every accelerometer device has this problem; guidelines say to move the person to the floor.
- The camera needs a side-on view and decent light.
- The AI debrief needs an Apple Intelligence device; otherwise it falls back to the rule text.
- iPhone + Apple Watch only (the web version runs on a laptop with a webcam).
- Not a medical device; making clinical claims would need validation and FDA clearance.
- Speech recognition can struggle in loud rooms. The emergency check has Yes/No buttons as a fallback.

---

## 10. Design decisions and why

| Decision | Why |
|---|---|
| Use pretrained models, don't train our own | No labelled real-CPR data; 36 hours; explainable for a safety tool; on-device and private |
| Physics and signal processing for depth | Interpretable, needs no training data, testable with synthetic signals |
| Rules for coaching, not an LLM | Predictable, instant, works offline; the LLM only rewrites measured facts in the debrief |
| Everything on the phone | Privacy (no video or voice leaves the phone), works offline, no laptop needed |
| Never coach on uncalibrated camera depth | A wrong "push harder" is worse than none |
| Simulated 911 call | Safe for demos and testing |
| 6 s gap between spoken cues | Users said it talked too much; coaching should guide, not nag |
| ±0.3 cm tolerance on depth | About our measurement error; avoids flicking between "on target" and not |
| Fatigue warning needs statistical significance | Noise of ±0.5 cm per compression caused false alarms |
| Voice + big buttons | Hands are busy, but voice can fail in noise |

---

## 11. Timeline (from git, October 24–25)

| Time | Milestone |
|---|---|
| 10:58 | M0 scaffolding: FastAPI, Vite dashboard, shared targets |
| 11:05 | M1 camera-only MVP: pose, posture, camera compressions, coaching, speech, metronome |
| 11:15 | M2 backend signal processing, watch simulator, watch-first fusion |
| 11:22 | M3 watch app, iPhone relay, setup guide |
| 11:37 | M4 calibration wizard, sessions, scorecard, leaderboard, record and replay |
| 11:53 | M5 demo hardening |
| 13:49–15:49 | XcodeGen project; real watch on device; clock offset, workout race and camera start fixes; real recordings |
| 16:09 | **Standalone phone coach** (no laptop) |
| 16:15–16:49 | UI redesign; "don't coach on camera-only depth" |
| 17:07 | Emergency mode, watch + camera fusion (EKF), debrief, accuracy validation tool |
| 17:12 | Emergency call made a simulation |
| 17:30 | Voice commands, spoken emergency check, recoil detection, 7 languages |
| 18:03 | Fatigue forecast, AED timeline, paramedic report, skills check, Siri, Live Activity, watch coaching |
| 18:19 | Web version gets the same features |
| 21:35–21:53 | Depth tolerance; widest camera view; 3D elbow angle; watch speaks |
| 22:01–22:24 | Video script; compact controls |
| 01:21 (Oct 25) | Voice heard over the coach; quieter coaching; compact top bar |
| 01:40–01:49 | Final README, video link, fact-check |

---

## 12. Future work (in priority order)

1. **Validate:** a training manikin with true depth, then a user study (untrained people, with and without the app).
2. **Soft surfaces:** use the camera to track the patient's chest against the floor, or detect a bed and tell the rescuer to move the person.
3. **Real emergency integration:** send location and the report to 911 dispatch (for example, through RapidSOS); show an AED map and send a second helper; alert nearby trained responders (like PulsePoint).
4. **Better coaching:** two-rescuer mode with two watches, rescue-breath quality from the camera, coaching through AirPods, personalised fatigue prediction, accessibility.
5. **Reach:** Android and Wear OS, metric camera-only mode for people without a watch, more languages.
6. **Training:** skills checks for schools and workplaces, an instructor dashboard, refresher reminders.
7. **Regulatory and partners:** clinical validation and FDA clearance for medical claims; pilots with AHA, the Red Cross or EMS agencies.
8. **With labelled data:** train a model to correct depth for surface, body size and watch fit, and to detect leaning more reliably.

---

## 13. Question bank

### Judge and technical questions

- **How accurate is it?** About 0.2 cm and ±1/min in simulation; not yet on a manikin; that's next.
- **What's a Kalman filter?** It blends the drifting-but-precise watch with the steady-but-unscaled camera, trusting each where it's strongest. The camera learns its scale from the watch.
- **What CV and ML do you use? How did you train it?** We didn't train models. We used Apple Vision 2D + 3D pose, Apple speech recognition and Apple's on-device LLM, all pretrained. Our work is the signal processing, the EKF, the clock sync and the coaching rules on top.
- **Why not train a model?** No labelled real-CPR data, the time limit, and explainability for a safety tool.
- **No Apple Watch?** Camera-only mode: rate and form, plus an estimated depth that's never used for depth coaching. A scale learned earlier carries over.
- **Soft surface?** It reads high, the same as all accelerometer devices. The fix is the floor, or camera chest tracking in future.
- **Privacy?** Pose, speech, coaching and the debrief all run on the phone. Nothing is uploaded.
- **Medical device?** No. It's a coaching and training tool, and the call is simulated.
- **Latency?** Watch packets every 200 ms, evaluation every 250 ms, spoken cues at least 6 s apart.
- **Why not the phone on the chest?** It slides, gets in the way, and can't see your form. The watch is already on the pushing hand.
- **How does it know you're tired?** A trend line, a significance test and a 5 s hold.
- **Who's it for?** Family members at home (about 7 in 10 arrests), plus schools and training.
- **Business model?** Free for emergencies; paid training (skills checks, instructor dashboards).

### Job interview (behavioural) prompts

- **"Tell me about a project you're proud of."** Use the 2-minute pitch in section 1.
- **"Hardest bug?"** The 40 ms clock gap (challenge 2): a 10% error that looked like a math problem but was a timing problem. Found by measuring, fixed with cross-correlation.
- **"A time you used data to make a decision."** Fatigue false alarms: measured 6 in 100, added a statistical test, verified 0 in 100.
- **"A trade-off you made."** Not coaching on uncalibrated camera depth (accuracy and safety over features), or rules instead of an LLM for live coaching.
- **"What would you do differently?"** Get a manikin with true depth on day 1, so accuracy is measured against reality from the start, not only in simulation.
- **"How did you handle scope?"** Milestone 1 had to work with no Apple hardware, and a simulator plus replay meant the demo never depended on live hardware.
- **"Who did what?"** Fill this in together:
  - Aaron Zheng: ...
  - Jaeha Lee: ...
  - Eason Zheng: ...
- **"Did you use AI tools?"** Decide your honest answer as a team beforehand and give it plainly.

---

## 14. Repository map

```
apple/                     iPhone + Apple Watch apps (XcodeGen: project.yml)
  Sources/Watch/           motion streaming, CPR1 packets, workout, on-watch coach, metronome
  Sources/Core/            watch signal pipeline (WatchDSP), config and targets, localisation
  Sources/iOS/Coach/       camera pose, depth fusion (EKF), coaching logic, voice, audio, debrief,
                           paramedic report, demo replay, Siri + Live Activity, UI
  Sources/Widgets/         Live Activity
  SETUP.md                 device setup with a free Apple ID
web/src/                   React app: pose/, fusion/, coach/, voice/, i18n/, session/, components/
backend/app/               FastAPI server, ingest, dsp/ (filters, compressions, depth, fatigue), session scoring
backend/tools/             simulator, record, replay, validate
backend/tests/             56 pytest tests
shared/targets.json        AHA targets shared by web and backend
recordings/                recorded watch sessions for replay
demo/                      video script, app screenshots
docs/                      laptop dashboard guide, this inventory
PRD.md                     the original spec
```
