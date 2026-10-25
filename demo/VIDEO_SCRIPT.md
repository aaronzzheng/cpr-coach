# CPR Coach: final 3-minute video script

HackOHI/O 2026 · due **10:00 AM Sunday** · MP4 · ≤ 500 MB · 3:00 max · must show the key
features **and** the technical challenges we overcame. A live 6-minute Q&A follows, so every line
here is something we can show or explain on the spot.

**Who's who:** *VO* = voiceover, recorded last over the edit. *App* = the app's own voice (keep it
audible). *Rescuer* = the person doing CPR on camera.

**Equipment:** Phone A = Jaeha's iPhone with CPR Coach, recording its own screen (Control Center ›
Screen Recording, long-press › **Microphone on**). Phone B = any phone, filming (tripod for wide
shots, handheld for close-ups). Laptop = presenting the deck full screen and screen-recording it.

---

## The script, second by second

### 0:00 – 0:03 · SLIDE 1 “CPR Coach” (cover)
**VO:** “This is CPR Coach.”

### 0:03 – 0:15 · CLIP A (3 s) → SLIDE 2 “Most people never get CPR in time”
**Clip A (Phone B, wide):** someone slumps to the floor; a bystander kneels beside them, unsure what to do. Cut to the slide.
**VO:** “Every year, about 263,000 Americans have a cardiac arrest outside a hospital. Only about four in ten get CPR from a bystander, and survival drops up to ten percent for every minute without it.”
*Rubric: Impact*

### 0:15 – 0:29 · SLIDE 3 “What exists today, and where it falls short”
**VO:** “We researched what already exists. Classes only help in training. Professional feedback devices sit under your hands and can misread depth. A phone-on-chest app didn’t help at all in a 240-person trial. And a 911 dispatcher can’t see you.”
*Rubric: Innovation*

### 0:29 – 0:37 · SLIDE 4 “Three sensors you already own” → CLIP B (3 s)
**Clip B (Phone B):** the rescuer props Phone A on the floor beside the “patient”, watch visible on the wrist.
**VO:** “So we built CPR Coach. Your iPhone camera sees your form, your Apple Watch feels every push, and you control it with your voice.”
*Rubric: Communication*

### 0:37 – 1:25 · LIVE DEMO (Clips C, D) · the heart of the video
Edit: Phone B’s wide shot full frame, Phone A’s screen recording as picture-in-picture in a corner.
Keep the **app’s voice audible**; VO only in the gaps marked below. Trim pauses tight.

| Time | Rescuer does / says | App says / shows | VO (in the gap) |
|---|---|---|---|
| 0:37 | “Hey Siri, start CPR with CPR Coach.” | Emergency screen opens | “Hands-free, from the first second.” |
| 0:40 | Taps the “patient”’s shoulders | “Tap their shoulders and shout. Are they responding? Say yes or no.” | |
| 0:44 | “No.” | “Are they breathing normally? Gasping doesn’t count…” | |
| 0:48 | “No.” | “No normal breathing. Calling for help. Start compressions now…” · green call pill + metronome | “It checks the person with you and gets help coming.” |
| 0:53 | Compresses with **bent elbows** | “Lock your elbows.” · arm lines turn orange | |
| 0:57 | Straightens arms, then compresses **slowly** | “Faster.” | |
| 1:01 | Speeds up to the beat | Rate tile turns green, “On target” | “It coaches every compression: form, rate and depth.” |
| 1:05 | “How am I doing?” | “Rate 112. Depth 5.4 centimetres. Looking good, keep going.” | |
| 1:10 | **Clip D** (Phone B close-up on the watch) | Watch shows the cue; wrist tap | “The watch coaches too, with a tap on the wrist…” |
| 1:15 | Presses Phone A’s side button | Lock screen shows rate, depth, instruction | “…and the session stays on your lock screen.” |
| 1:18 | Unlocks, taps **AED** | Pad-placement guide | “When the AED arrives, it shows where the pads go.” |
| 1:21 | “Stop.” Taps **Report for paramedics** | Timeline, stats, QR code | “And paramedics get a full report.” |

*Rubric: Communication (working prototype), Impact*

### 1:25 – 1:35 · SLIDE 5 “How it works”
**VO:** “Under the hood, the watch processes motion a hundred times a second, and the phone runs body tracking, our coaching engine, speech and an on-device AI. No internet needed.”
*Rubric: Communication, Breadth & Complexity*

### 1:35 – 1:47 · SLIDE 6 “Watch + camera, fused into true depth” → CLIP E (2 s)
**Clip E (Phone A):** the depth tile reading **“Watch + camera”**.
**VO:** “The hardest part was depth. The watch is precise but drifts; the camera never drifts but can’t measure centimetres. A Kalman filter fuses them, and the camera learns its own scale from the watch.”
*Rubric: Breadth & Complexity*

### 1:47 – 1:59 · SLIDE 7 “The questions we asked” → CLIP F (3 s)
**Clip F (Phone A):** the **“Switch soon”** banner appearing.
**VO:** “Every feature started as a question. Can we see fatigue coming? It forecasts your depth trend and tells you to switch rescuers before your compressions get shallow.”
*Rubric: Curiosity*

### 1:59 – 2:15 · SLIDE 8 “What broke, and how we pivoted”
**VO:** “Plenty broke. Camera-only depth swung from two to nine centimetres, so we fused it with the watch. A forty-millisecond clock gap caused a ten percent error, so we sync the clocks by cross-correlation. And Apple blocked our watch app without a paid account, so we rebuilt it and side-loaded it onto a 2019 watch.”
*Rubric: Navigating Challenges (the video brief requires this)*

### 2:15 – 2:25 · SLIDE 9 “Medicine, physics, AI and design” → CLIPS G, H (4 s)
**Clip G (Phone A):** language set to Español; the coach speaks Spanish (let 2 s play).
**Clip H (Phone A):** tapping **Infant**; the depth target changes.
**VO:** “It brings together emergency medicine, physics, signal processing and computer vision, in seven languages, for adults, children and infants.”
*Rubric: Breadth & Complexity*

### 2:25 – 2:35 · SLIDE 10 “Measured against known rates and depths”
**VO (with numbers):** “We tested it against a click track and a five-centimetre stop: [__] percent of compressions within five per minute, and [__] percent within half a centimetre.”
**VO (if the trials aren’t done):** “In simulation, fused depth stayed within a fifth of a centimetre, and we’re validating on real compressions next.” *(then change the slide’s two big numbers to “0.2 cm” and “±1%” and its labels to match)*
*Rubric: Curiosity (testing)*

### 2:35 – 2:52 · SLIDE 11 “Who it helps” → CLIP I (4 s)
**Clip I (Phone B):** a real tester after trying it, one sentence to camera.
**VO:** “It needs no new hardware, just the phone and watch people already wear.” *(Clip I plays)* “Next, we’d send the report straight to 911 dispatch and guide a second helper to the nearest AED.”
**If you have no tester:** drop Clip I and remove the quote column from the slide.
*Rubric: Impact*

### 2:52 – 3:00 · SLIDE 12 “The best CPR coach is the one already on your wrist”
**VO:** “CPR Coach. The best CPR coach is the one already on your wrist.”

---

## Shooting list (in the most efficient order)

1. **Slides (laptop):** present the deck full screen, screen-record ~10 s on each of the 12 slides. Trim in the edit.
2. **Clip C + D, the live demo (Phone A screen recording + Phone B):** set up first: phone propped side-on about 1.5 m away (landscape if possible), watch app open, phone unlocked, volume up. Do 2–3 full takes of the table above; keep the cleanest.
   - Siri tip: if “Hey Siri” isn’t recognised yet, start the screen recording and tap **Someone collapsed?** instead, then cut the Siri moment.
3. **Clip E:** a normal session with a clear side view for 1–2 minutes until the depth tile reads “Watch + camera”. Keep the last few seconds.
4. **Clip F:** long-press **Watch** twice (two taps), **Start session**, hands off. “Switch soon” appears after ~40 s. Keep the moment it appears.
5. **Clip G:** 🌐 → Español, Start session, record 5 s of Spanish coaching. Switch back to English.
6. **Clip H:** tap **Infant** on the setup screen (2 s).
7. **Clip A:** the staged collapse (several takes, 3 s used).
8. **Clip B:** propping the phone up beside the patient (3 s).
9. **Clip I (optional):** a friend tries it for a minute, then says one honest sentence to camera.
10. **VO:** read the VO lines above in one quiet take, over the finished edit.

## Final checks before you export
- Total length ≤ 3:00. If over, shorten the demo pauses first, never the challenges slide.
- App voice audible in the demo; VO doesn’t talk over the app’s lines.
- Every slide readable with the sound off.
- MP4, 1080p, under 500 MB.
- Slide 10 has real numbers or the simulation wording; slide 11 has a real quote or no quote.

## Q&A cheat sheet (6 minutes live)
- **Inspiration:** most arrests happen at home, where the helper has no recent training and no feedback.
- **Hardest challenge:** fusing watch and camera (different clocks, units and noise): cross-correlation for the clock, a Kalman filter for the scale.
- **Accuracy:** the validation report; simulated fusion 0.14–0.21 cm median error; next step a clinical feedback manikin.
- **No watch?** Camera-only mode estimates depth from arm length; a scale learned earlier from the watch carries over.
- **Medical device?** No, a coach and training tool; the demo build never dials 911.
- **10× scale:** reports sent to 911 dispatch, AED maps, school and workplace skills checks, Android and Wear OS.
- **Privacy:** video, voice and the AI debrief stay on the phone.
- Keep the app and the deck open to show anything they ask about.
