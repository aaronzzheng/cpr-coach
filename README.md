# CPR Coach

**Real-time CPR coaching from the iPhone and Apple Watch you already own.**

HackOHI/O 2026 · Aaron Zheng, Jaeha Lee, Eason Zheng

> Training and coaching tool, not a medical device. The app never dials 911: the emergency call in the demo is simulated.

## Demo video

https://youtu.be/oubjYkOBK_0

## The problem

About 263,000 Americans have a cardiac arrest outside a hospital each year. Only about four in ten get CPR from a bystander, and survival drops by up to ten percent for every minute without it. Nothing today coaches you in the moment: classes only help in training, feedback devices sit under your hands and can misread depth, a phone-on-chest app made no difference in a 240-person trial, and a 911 dispatcher can't see you.

## What it does

<p>
  <img src="demo/shots/triage.png" width="200" alt="Emergency check: are they responding?">
  <img src="demo/shots/running.png" width="200" alt="Live coaching with rate and depth">
  <img src="demo/shots/aed.png" width="200" alt="AED pad placement guide">
  <img src="demo/shots/report.png" width="200" alt="Report for paramedics">
</p>

- **One tap to start.** It asks out loud whether the person is responding and breathing, you answer "yes" or "no", and it starts a simulated emergency call and a metronome.
- **Coaches every compression** on form, rate and depth: "Lock your elbows", "Faster", "Push harder".
- **Hands-free.** Ask "How am I doing?", "How long?", "Swap" or "Stop".
- **The watch coaches too**, with taps on your wrist.
- **Predicts fatigue** and tells you to switch rescuers before your compressions get shallow.
- **AED guide** that shows where the pads go.
- **Report for paramedics** with a timeline and a QR code when you stop.
- **Seven languages**, with modes for adults, children and infants.
- **On-device AI debrief** after a practice session, plus a two-minute skills check.

## How it works

The watch measures motion 100 times a second. The hard part is depth: the watch is precise but its estimate drifts, and the camera never drifts but can't measure centimetres. A Kalman filter fuses them, trusting each sensor where it's strongest, and the camera learns its own scale from the watch. Everything runs on the phone.

| Area | What we used |
|---|---|
| Apps | Swift 6 + SwiftUI (iPhone and Apple Watch), HealthKit, WatchConnectivity, Live Activities, App Intents |
| Computer vision | Apple Vision 2D + 3D body pose (true elbow angle at any camera tilt); MediaPipe Pose on the web |
| AI and ML | Apple Foundation Models (on-device debrief), speech recognition for voice commands, text to speech in 7 languages |
| Signal processing | Core Motion at 100 Hz, Kalman filter fusion, cross-correlation clock sync, least-squares fatigue forecast |
| Web and server | React + TypeScript, Web Speech API; Python, FastAPI, NumPy, SciPy |

## Challenges we overcame

Our first version had three big problems, and we tested every fix:

| Problem | Before | After | Fix |
|---|---|---|---|
| Camera-only depth | 2–9 cm spread | 0.2 cm error | Fused with the watch's motion sensor |
| 40 ms clock gap between phone and watch | 10% depth error | ±1% | Sync the clocks by cross-correlating their motion |
| Fatigue warning firing on rescuers who weren't tired | 6 in 100 sessions | 0 in 100 | Only warn when the drop is statistically clear and lasts 5 s |

## Accuracy

In our simulated test sessions, depth error was about ±0.2 cm and rate error about ±1 compression per minute, a small fraction of the target zones (5–6 cm and 100–120 per minute). Next, we validate it on a real CPR training manikin.

## Run it

**iPhone and Apple Watch app** (Xcode, a free Apple ID works):

```bash
brew install xcodegen
make apple-signing TEAM=<your team id> PREFIX=com.yourname
make apple-install          # builds and installs on the connected iPhone, with the watch app inside
```

Full steps, including the watch, are in [apple/SETUP.md](apple/SETUP.md).

**Web version and laptop dashboard** (Python 3.11+, Node 20+):

```bash
make setup
make dev                    # http://localhost:5173
make test                   # backend and web tests
```

Details, calibration and troubleshooting: [docs/web-dashboard.md](docs/web-dashboard.md). Full spec: [PRD.md](PRD.md).
