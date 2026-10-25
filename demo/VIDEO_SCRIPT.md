# CPR Coach: 3-minute judging video

HackOHI/O 2026. Due **10:00 AM Sunday**, MP4, ≤ 500 MB, 3:00 max. The video must show the key
features **and the technical challenges we overcame**. It is followed by a live 6-minute Q&A, so
every claim below is one we can back up on the spot.

Each section is tagged with the rubric criterion it earns (Innovation, Curiosity, Communication,
Breadth & Complexity, Impact, Navigating Challenges). Slides are in the deck in this order.

## Timeline and voiceover (~410 words)

| Time | Show | Rubric |
|---|---|---|
| 0:00–0:04 | Slide **cover** | |
| 0:04–0:16 | Slide **problem** → clip A (collapse) | Impact |
| 0:16–0:30 | Slide **existing** | Innovation |
| 0:30–0:38 | Slide **product** → clip B (setup) | Communication |
| 0:38–1:26 | Clips C + D (the full emergency, phone screen picture-in-picture) | Communication (working prototype) |
| 1:26–1:36 | Slide **architecture** | Communication, Complexity |
| 1:36–1:46 | Slide **fusion** → clip E (“Watch + camera”) | Complexity |
| 1:46–1:58 | Slide **questions** → clip F (“Switch soon”) | Curiosity |
| 1:58–2:14 | Slide **challenges** | Navigating Challenges |
| 2:14–2:24 | Slide **breadth** → clips G, H (Spanish, infant) | Breadth |
| 2:24–2:34 | Slide **accuracy** | Curiosity (testing) |
| 2:34–2:52 | Slide **impact** → clip I (a tester) | Impact |
| 2:52–3:00 | Slide **close** | |

**0:04 Problem.** “Every year about 263,000 Americans have a cardiac arrest outside the hospital. Only about four in ten get CPR from a bystander, and every minute without it cuts survival by up to ten percent. Most happen at home.”

**0:16 Existing solutions.** “We looked at what exists. Classes and feedback manikins only help in training. Professional feedback pucks use one accelerometer under your hands, and in a 240-person trial, a phone-on-chest app didn’t improve compressions at all. A 911 dispatcher can talk you through it, but can’t see you. So we asked: what if the coach could see you and feel every push, using devices people already own?”

**0:30 Product.** “CPR Coach turns your iPhone and Apple Watch into a CPR instructor.”

**0:38 Demo** (let the app’s own voice carry most of this; VO only in gaps). “Say ‘Hey Siri, start CPR’. It checks the person with you, gets help coming, then coaches every compression: elbows, rate, depth, recoil. Hands-free: ask how you’re doing. The watch taps the beat and corrects you on your wrist, the session stays on your lock screen, there’s an AED guide, and paramedics get a report with a QR code.”

**1:26 Architecture.** “The watch processes motion at 100 hertz. The phone runs body-pose tracking, our coaching engine, speech and an on-device language model, all without the internet.”

**1:36 Fusion.** “The hardest part: the watch measures depth precisely but drifts; the camera never drifts but can’t measure centimetres. A Kalman filter fuses them, and the camera learns its own scale from the watch.”

**1:46 Questions.** “Every feature started as a question. Can we see fatigue coming? Now it forecasts the depth trend and calls the swap before compressions get shallow.”

**1:58 Challenges.** “A lot broke. Camera-only depth swung from two to nine centimetres, so we fused it with the watch. A forty-millisecond clock gap caused a ten percent error, so we sync the clocks by cross-correlation. Apple blocked our watch app without a paid account, so we rebuilt it for watchOS 10 and side-loaded it onto a 2019 watch. And our fatigue alarm fired on steady rescuers until we added a significance test.”

**2:14 Breadth.** “It pulls together emergency medicine, physics, signal processing, computer vision and human factors, in seven languages, for adults, children and infants.”

**2:24 Accuracy.** “Tested against a click track and a five-centimetre stop: [__]% of compressions within five per minute, and [__]% within half a centimetre.”

**2:34 Impact.** “It needs no new hardware. Here’s what testers said: [one short quote]. Next: sending the handoff straight to 911 dispatch and a map to the nearest AED.”

**2:52 Close.** “CPR Coach. The best CPR coach is the one already on your wrist.”

## What to record

Phone A = Jaeha’s iPhone running CPR Coach, recording its own screen (Control Center › Screen
Recording, **microphone on**). Phone B = any phone on a tripod or handheld.

| Clip | Camera | What | Length used |
|---|---|---|---|
| A | B | Someone slumps to the floor; a bystander kneels, unsure | 4 s |
| B | B | Phone A propped on the floor beside the “patient”, watch on the wrist | 4 s |
| C | A + B together | The full emergency, one take: “Hey Siri, start CPR with CPR Coach” → “no” → “no” → call pill → compress → bend elbows (“Lock your elbows”) → go slow (“Faster”) → “How am I doing?” → tap **AED** (2 s) → side button for the lock screen → unlock → “stop” → **Report for paramedics**, hold on the QR code | 40 s |
| D | B, handheld | Watch close-up while compressing slowly: the cue and the wrist tap | 6 s |
| E | A | A normal session with a clear side view until the depth tile reads **“Watch + camera”** | 4 s |
| F | A | Long-press **Watch** twice, Start session, don’t compress; keep the moment **“Switch soon”** appears (~40 s) | 4 s |
| G | A | 🌐 → Español, start a session, the coach speaks Spanish | 5 s |
| H | A | Tap **Infant**; the depth target changes | 3 s |
| I | B | A real tester (ideally CPR-certified) tries it and says one sentence about it, on camera | 8 s |
| J | A | Optional: the **Debrief** card and a **Passed** skills check, for the debrief and skills claims | 4 s |
| Slides | Laptop | Present the deck full screen and screen-record each slide for ~10 s; trim in the edit | — |

Tips:
- Clip C is the heart of the video. Do two or three takes and keep the cleanest.
- Fatigue (F) needs ~40 s of waiting; cut to the moment the banner appears.
- Record the voiceover last, over the edited cut. Keep the app’s own voice audible in clip C.
- Export MP4, 1080p, under 500 MB. Watch the final once with sound off: every slide must be readable on its own.

## Fill in before exporting
- **Accuracy slide + VO:** run `make validate RATE=100`, `RATE=120`, `DEPTH=5`, then `make validate-report`. Use the report’s two percentages. If a number is weaker than you’d like, keep it real and say “in early testing”; judges respect it and can check it.
- **Impact slide:** two real tester quotes (name, role) and one change you made from their feedback. Ten minutes with two friends is enough; a CPR-certified one is gold.

## Q&A prep (6 minutes, live)
- **What inspired it?** Most arrests happen at home, and the person there usually has no recent training and no feedback.
- **Hardest technical challenge?** Fusing watch and camera: different clocks, units and noise. Cross-correlation for the clock, a Kalman filter for the scale.
- **How accurate is it?** Validation numbers from the report; synthetic fusion tests at 0.14–0.21 cm median error. Next step is a clinical feedback manikin as ground truth.
- **What if there’s no watch?** Camera-only mode estimates depth from arm length, and if the watch was used earlier, the camera keeps the scale it learned.
- **Is it a medical device?** No: a coach and training tool. The demo build never dials 911.
- **How does it scale (10×)?** Send the handoff to dispatch, AED map, school and workplace skills checks, Android + Wear OS.
- **Privacy?** Video, voice and the AI debrief all stay on the phone.
- Keep the app and the deck open during Q&A to show anything they ask about.
