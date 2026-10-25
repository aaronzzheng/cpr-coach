# CPR Coach: final 3-minute video script

HackOHI/O 2026 · due **10:00 AM Sunday** · MP4 · ≤ 500 MB · 3:00 max · must show the key
features **and** the technical challenges we overcame. A live 6-minute Q&A follows.

**6 slides, ~65 s. The app itself, ~72 s.** Runs about 2:40, leaving ~20 s of slack for pauses.
Slide images: `~/Downloads/CPR Coach Video Slides/` (1920×1080 PNGs + a PDF).

*VO* = voiceover, recorded last over the edit. *App* = the app's own voice (keep it audible).

---

## 0:00 – 0:03 · CLIP: collapse
Phone B, wide: someone slumps to the floor; a bystander kneels beside them, unsure. No VO.

## 0:03 – 0:15 · SLIDE 1 · Problem
**VO:** "Every year, about 263,000 Americans have a cardiac arrest outside a hospital. Only about four in ten get CPR from a bystander, and survival drops up to ten percent for every minute without it."
*Impact*

## 0:15 – 0:28 · SLIDE 2 · Existing solutions
**VO:** "We researched what already exists. Classes only help in training. Professional feedback devices sit under your hands and can misread depth. A phone-on-chest app didn't help at all in a 240-person trial. And a 911 dispatcher can't see you."
*Innovation*

## 0:28 – 1:40 · LIVE DEMO
Edit: Phone B's wide shot full screen, Phone A's screen recording picture-in-picture. Keep the app's voice audible; VO only in the gaps.

| Time | On screen / rescuer | App says / shows | VO |
|---|---|---|---|
| 0:28 | Rescuer props the phone up beside the patient, watch on wrist | | "So we built CPR Coach. Your iPhone's camera sees your form, and your Apple Watch feels every push." |
| 0:33 | Taps **Someone collapsed?** | Emergency screen | "One tap, and it takes over." |
| 0:35 | Taps the patient's shoulders | "Are they responding? Say yes or no." | |
| 0:39 | "No." | "Are they breathing normally? Gasping doesn't count…" | |
| 0:43 | "No." | "No normal breathing. Calling for help. Start compressions now…" · call pill + metronome | "It checks the person with you and gets help coming." |
| 0:50 | Compresses with **bent elbows** | "Lock your elbows." | |
| 0:54 | Straightens, then compresses **slowly** | "Faster." | |
| 0:58 | Speeds up to the beat | Rate turns green | "It coaches every compression: form, rate and depth." |
| 1:02 | "How am I doing?" | Reads back rate and depth | |
| 1:07 | Close-up of the **watch** | Cue + wrist tap | "The watch coaches too, with a tap on the wrist," |
| 1:11 | Side button on the phone | Lock screen session | "and the session stays on your lock screen." |
| 1:14 | Unlocks, taps **AED** | Pad guide | "When the AED arrives, it shows where the pads go," |
| 1:17 | "Stop." → **Report for paramedics** | Timeline + QR code | "and paramedics get a full report." |
| 1:22 | Cut: **"Switch soon"** banner (fatigue replay) | | "It even predicts fatigue, telling you to switch before your compressions get shallow." |
| 1:29 | Cut: Spanish coaching (2 s), then tapping **Infant** (2 s) | Spanish voice | "In seven languages, for adults, children and infants." |
| 1:34 | Optional: a tester, one sentence to camera | | |

*Communication (working prototype), Impact, Curiosity*

## 1:40 – 1:56 · SLIDE 3 · How it works
**VO:** "Under the hood, the watch measures motion a hundred times a second. The hardest part was depth: the watch is precise but drifts, and the camera never drifts but can't measure centimetres. So a Kalman filter fuses them, and the camera learns its own scale from the watch, all on the phone."
*Breadth & Complexity, Communication*

## 1:56 – 2:16 · SLIDE 4 · Challenges
**VO:** "Every feature started as a question, and plenty broke along the way. Camera-only depth swung from two to nine centimetres, so we fused it with the watch. A forty-millisecond clock gap caused a ten percent error, so we sync the clocks by cross-correlation. And Apple blocked our watch app without a paid account, so we rebuilt it and side-loaded it onto a 2019 watch."
*Navigating Challenges, Curiosity*

## 2:16 – 2:26 · SLIDE 5 · Accuracy
**VO (with numbers):** "We tested it against a click track and a five-centimetre stop: [__] percent of compressions within five per minute, and [__] percent within half a centimetre."
**VO (if the trials aren't done):** "In simulation, fused depth stayed within a fifth of a centimetre, and we're validating on real compressions next."

## 2:26 – 2:40 · SLIDE 6 · Close
**VO:** "It needs no new hardware, just the phone and watch people already wear. Next, we'd send the report straight to 911 dispatch and guide a second helper to the nearest AED. CPR Coach: the best CPR coach is the one already on your wrist."
*Impact*

---

## What to record, in shooting order
1. **Live demo (0:28–1:22):** Phone A records its own screen (Control Center › Screen Recording, microphone on); Phone B films the rescuer wide. Prop Phone A side-on ~1.5 m away (landscape if you can), watch app open, volume up. Do 2–3 full takes; film the watch close-up with Phone B during the "Faster" moment.
2. **"Switch soon":** long-press **Watch** twice, Start session, hands off; it appears at ~40 s.
3. **Spanish:** 🌐 → Español, start a session, 5 s of coaching. Switch back.
4. **Infant:** tap Infant on the setup screen.
5. **Collapse:** the staged collapse (3 s used).
6. **Tester (optional):** a friend tries it, then says one sentence.
7. **VO:** read all VO lines last, in one quiet take, over the edit.

The slides are already exported as images: drop them straight into the editor.

## Before you export
- 3:00 or under (the plan runs ~2:40; use the slack to let the demo breathe).
- App voice audible in the demo; VO never talks over it.
- Slide 5 has real numbers or the simulation wording.
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
