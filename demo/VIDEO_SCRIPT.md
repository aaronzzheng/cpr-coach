# CPR Coach: final 3-minute video script

HackOHI/O 2026 · Aaron Zheng and Jaeha Lee · due **10:00 AM Sunday** · MP4 · ≤ 500 MB · 3:00 max ·
must show the key features **and** the technical challenges we overcame. A live 6-minute Q&A follows.

**8 slides, ~75 s. The app itself, ~64 s.** Runs about 2:55, leaving ~5 s of slack (skip the optional tester if a take runs long).
Slide images: `~/Downloads/CPR Coach Video Slides/` (1920×1080 PNGs + a PDF).

*VO* = voiceover, recorded last over the edit. *App* = the app's own voice (keep it audible).

---

## 0:00 – 0:03 · CLIP: collapse
Phone B, wide: someone slumps to the floor; a bystander kneels beside them, unsure. No VO.

## 0:03 – 0:08 · SLIDE 1 · Intro
**VO:** "Hi, we're Aaron Zheng and Jaeha Lee, and this is CPR Coach."
*Communication*

## 0:08 – 0:20 · SLIDE 2 · Problem
**VO:** "Every year, about 263,000 Americans have a cardiac arrest outside a hospital. Only about four in ten get CPR from a bystander, and survival drops up to ten percent for every minute without it."
*Impact*

## 0:20 – 0:33 · SLIDE 3 · Existing solutions
**VO:** "We researched what already exists. Classes only help in training. Professional feedback devices sit under your hands and can misread depth. A phone-on-chest app didn't help at all in a 240-person trial. And a 911 dispatcher can't see you."
*Innovation*

## 0:33 – 1:37 · LIVE DEMO
Edit: Phone B's wide shot full screen, Phone A's screen recording picture-in-picture. Keep the app's voice audible; VO only in the gaps.

| Time | On screen / rescuer | App says / shows | VO |
|---|---|---|---|
| 0:33 | Rescuer props the phone up beside the patient, watch on wrist | | "So we built CPR Coach. Your iPhone's camera sees your form, and your Apple Watch feels every push." |
| 0:38 | Taps **Someone collapsed?** | Emergency screen | "One tap, and it takes over." |
| 0:40 | Taps the patient's shoulders | "Are they responding? Say yes or no." | |
| 0:44 | "No." | "Are they breathing normally? Gasping doesn't count…" | |
| 0:48 | "No." | "No normal breathing. Calling for help. Start compressions now…" · call pill + metronome | "It checks the person with you and gets help coming." |
| 0:55 | Compresses with **bent elbows** | "Lock your elbows." | |
| 1:01 | Straightens, then compresses **slowly** | "Faster." | |
| 1:05 | Speeds up to the beat | Rate turns green | "It coaches every compression: form, rate and depth." |
| 1:09 | "How am I doing?" | Reads back rate and depth | |
| 1:14 | Close-up of the **watch** | Cue + wrist tap | "The watch coaches too, with a tap on the wrist." |
| 1:18 | Taps **AED** | Pad guide | "When the AED arrives, it shows where the pads go." |
| 1:22 | Says **"Stop."** | "Stopped." · session ends | |
| 1:24 | The **full report** opens | Timeline + QR code | "And when you stop, paramedics get a full report of everything that happened." |
| 1:29 | Cut: Spanish coaching (2 s), then tapping **Infant** (2 s) | Spanish voice | "It coaches in seven languages, for adults, children and infants." |
| 1:34 | Optional: a tester, one sentence to camera | | |

*Communication (working prototype), Impact, Curiosity*

## 1:37 – 1:51 · SLIDE 4 · How it works
**VO:** "Under the hood, the watch measures motion a hundred times a second. The hardest part was depth: the watch is precise but drifts, and the camera never drifts but can't measure centimetres. So a Kalman filter blends them, trusting each sensor where it's strongest, and the camera learns its own scale from the watch, all on the phone."
*Breadth & Complexity, Communication*

## 1:51 – 2:03 · SLIDE 5 · Tech stack
**VO:** "We built it in Swift for iPhone and Apple Watch, with Apple's Vision for body tracking, an on-device AI model for your debrief, and voice coaching in seven languages."
*Breadth & Complexity*

## 2:03 – 2:35 · SLIDE 6 · Challenges
**VO:** "Our first version had three big problems, and we tested every fix. First, the camera alone can't measure distance, so its depth readings ranged from two to nine centimetres. Fusing it with the watch's motion sensor brought the error down to two millimetres in our tests. Second, the phone and watch clocks were 40 milliseconds apart, which threw depth off by ten percent, so we now sync them by matching their motion. Third, our fatigue warning went off for rescuers who weren't tired. Now it only warns when the drop in depth is clear and lasts five seconds, and false alarms fell from six in a hundred to zero."
*Navigating Challenges, Curiosity*

## 2:35 – 2:47 · SLIDE 7 · Accuracy
**VO:** "In simulated tests, depth was off by about two millimetres and rate by one compression a minute. Next: testing on a real manikin."
*Curiosity*

## 2:47 – 2:55 · SLIDE 8 · Thank you
**VO:** "With the phone and watch people already own, CPR Coach helps anyone give better CPR until help arrives. Thanks for watching."
*Communication, Impact*

---

## What to record, in shooting order
1. **Live demo (0:33–1:27):** one continuous take, no lock-screen step: Phone A records its own screen (Control Center › Screen Recording, long-press, microphone on); Phone B films the rescuer wide. Prop Phone A side-on ~1.5 m away, watch app open, volume up. Use a pillow or rolled towel on the "patient's" chest. Do 2–3 full takes; film the watch close-up with Phone B during the "Faster" moment.
2. **Spanish:** 🌐 → Español, start a session, 5 s of coaching. Switch back.
3. **Infant:** tap Infant on the setup screen.
4. **Collapse:** the staged collapse (3 s used).
5. **Tester (optional):** a friend tries it, then says one sentence.
6. **VO:** read all VO lines last, in one quiet take, over the edit. Aaron and Jaeha can split them (for example, one reads slides 1–3 and the demo, the other reads slides 4–8).

The slides are already exported as images: drop them straight into the editor.

## Before you export
- 3:00 or under (the plan runs ~2:55; use the slack to let the demo breathe).
- App voice audible in the demo; VO never talks over it.
- Slide 7 (Accuracy) keeps the "simulated tests" wording unless you have real manikin numbers.
- MP4, 1080p, under 500 MB, by 10:00 AM.

## Q&A cheat sheet
- **Inspiration:** most arrests happen at home, where the helper has no recent training and no feedback.
- **Hardest challenge:** fusing watch and camera: cross-correlation for the clock, a Kalman filter for the scale.
- **Accuracy:** the validation report; simulated fusion 0.14–0.21 cm median error; next, a clinical feedback manikin.
- **No watch?** Camera-only mode; a scale learned earlier from the watch carries over.
- **Medical device?** No, a coach and training tool; the demo never dials 911.
- **10× scale:** reports to 911 dispatch, AED maps, school skills checks, Android and Wear OS.
- **Privacy:** video, voice and the AI debrief stay on the phone.
- The hidden slides in the deck (questions, breadth, impact…) are handy to screen-share in Q&A.
