# Apple setup (human steps)

All the Swift code is already written. You need to do the parts that require Xcode clicks,
your Apple ID, and the physical devices. **Do steps 1–3 early — the first watch install can take 5–15 minutes.**

Everything else (dashboard, backend, simulator) works without any of this.

Your hardware: **Apple Watch Series 5 (A2157) → max watchOS 10**, so the watch target must be **watchOS 10.0**.
Your Xcode 27 can still target watchOS 10 (its watchOS SDK supports deployment back to 9.0).

---

## 1. Create the Xcode project (≈5 min)

1. Open **Xcode → File → New → Project…**
2. Pick the **watchOS** tab → **App** → **Next**.
3. Fill in:
   - Product Name: **`CPRCoach`** (exactly, it matters for the install script)
   - Team: your **Personal Team** (a free Apple ID works) — add it via *Add Account…* if missing
   - Organization Identifier: e.g. `com.yourname`
   - Watch App type: **Watch App with New Companion iOS App**
   - Interface: **SwiftUI**, Language: **Swift**
   - Leave *Include Tests* unchecked
4. **Next** → navigate to `cpr-coach/apple/` → make sure *Create Git repository* is **unchecked** → **Create**.

   You should now have `cpr-coach/apple/CPRCoach/CPRCoach.xcodeproj`.

5. **Quit Xcode**, then in Terminal:

   ```bash
   cd cpr-coach/apple && ./install-sources.sh
   ```

   This replaces Xcode's template files with the real ones. Reopen `CPRCoach.xcodeproj`.

## 2. Configure the targets (≈10 min)

Click the blue **CPRCoach** project icon at the top of the file navigator, then work through each target in the left column of the editor.

### Watch target — "CPRCoach Watch App"

1. **General** tab → *Minimum Deployments* → **watchOS 10.0**.
2. **Signing & Capabilities** tab:
   - Team: your Personal Team. Bundle ID should be `com.yourname.CPRCoach.watchkitapp` (Xcode fills it in).
   - Click **+ Capability** → **HealthKit**.
   - Click **+ Capability** → **Background Modes** → tick **Workout processing**.
3. **Info** tab → hover any row under *Custom Target Properties* → click **+** and add these three (type the name, pick it from the list, then enter the text as the value):

   | Key | Value |
   |---|---|
   | Privacy - Health Share Usage Description | `Reads your heart rate during CPR practice.` |
   | Privacy - Health Update Usage Description | `Saves your CPR practice as a workout.` |
   | Privacy - Motion Usage Description | `Measures chest compression rate and depth from wrist motion.` |

### iOS target — "CPRCoach"

1. **General** tab → *Minimum Deployments* → **iOS 17.0**.
2. **Signing & Capabilities** tab:
   - Team: your Personal Team.
   - **+ Capability** → **HealthKit** (needed for the watch's Health permission flow).
3. **Info** tab → add:

   | Key | Type | Value |
   |---|---|---|
   | Privacy - Local Network Usage Description | String | `Connects to the CPR Coach laptop on your local network.` |
   | Privacy - Health Share Usage Description | String | `Reads your heart rate during CPR practice.` |
   | Privacy - Health Update Usage Description | String | `Saves your CPR practice as a workout.` |
   | App Transport Security Settings | Dictionary | *(add the two children below)* |

   Expand **App Transport Security Settings** (click its triangle), hover it, click **+** twice and add:
   - **Allows Local Networking** → `YES`
   - **Allow Arbitrary Loads** → `YES` (hackathon only — lets plain `ws://` reach a raw IP)

4. **Build check:** pick the **CPRCoach** scheme and *Any iOS Device* at the top, then **Product → Build** (⌘B). Then switch to the **CPRCoach Watch App** scheme and build again. Both should succeed.
   If HealthKit makes signing fail with a free account, remove the HealthKit capability from both targets and build again. The app still streams motion data; it just can't keep running at full rate with the screen off, so keep your wrist turned up.

## 3. Devices (≈10–20 min, mostly waiting)

1. **iPhone:** Settings → Privacy & Security → **Developer Mode** → on → restart → confirm.
2. Connect the iPhone to the Mac with a cable. Unlock it and tap **Trust**.
3. **Watch:** keep it on its charger, near the phone, **unlocked**. In Xcode → **Window → Devices and Simulators**, wait for the watch to appear under the iPhone (it may say "Preparing…" for several minutes).
4. **Watch:** Settings → Privacy & Security → **Developer Mode** → on (this option shows up once Xcode has talked to the watch; the watch restarts).
5. Run the **CPRCoach** scheme on the **iPhone** (▶︎). First time with a free account: iPhone → Settings → General → **VPN & Device Management** → your Apple ID → **Trust**. Run again.
6. Run the **CPRCoach Watch App** scheme on the **watch**. The first install is slow (5–15 minutes). If it stalls, see Troubleshooting below.

## 4. Connect everything

1. On the Mac: `make dev` (from `cpr-coach/`). Allow incoming connections if macOS asks about Python.
2. Get the laptop's IP:

   ```bash
   ipconfig getifaddr en0
   ```

3. **iPhone app:** type `ws://<that IP>:8000/ingest` → **Connect**. *Socket* should say **connected**, and the dashboard's **Phone** pill turns green. Allow *Local Network* access if iOS asks.
4. **Watch app:** tap **Start**. Allow the Health permissions. You should see *Phone: connected* and *Samples sent* going up by about 100/s. The dashboard's **Watch** pill turns green and the waveform moves.
5. **Round-trip check:** on the dashboard press **Space**. The watch should get "start" (already running is fine) and tap the metronome. Press **B** and the watch metronome should stop and restart.

**M3 is done when** real compressions with the watch on show live rate and depth on the dashboard, with 1% gaps or fewer over 2 minutes. Press **D** on the dashboard to see the packet rate (should be about 5/s) and the gap count.

## Troubleshooting

| Symptom | Fix |
|---|---|
| iPhone app stuck on *connecting…* | Hackathon Wi-Fi often blocks device-to-device traffic. Turn on the iPhone's **Personal Hotspot**, join it from the Mac, run `ipconfig getifaddr en0` again (you'll get something like `172.20.10.x`), and use that address. |
| Still can't connect | macOS firewall: System Settings → Network → Firewall → allow Python. Check `curl http://<IP>:8000/api/health` from another device. |
| Watch says *Phone: not reachable* | Open the iPhone app and keep it in the foreground. Bluetooth must be on. |
| Watch never appears in Xcode / install hangs | Mac and iPhone on the same network (the hotspot trick works here too), watch unlocked and on its charger, and **Window → Devices and Simulators → watch → Unpair/Re-pair in Xcode** as a last resort. |
| "Could not launch… untrusted developer" | iPhone → Settings → General → VPN & Device Management → Trust. |
| Watch haptic metronome misses beats | Turn on **Haptic every 2 beats** on the watch. The laptop's audio metronome is the primary one. |
| Depth reads too high or low | Expected before calibration (M4). The ruler calibration fixes the scale. |
| App stops working after 7 days | Free-account builds expire. Run from Xcode again. |

## What's in the code

| File | Target | Role |
|---|---|---|
| `CPRCoachWatchApp.swift` | Watch | App entry + `WatchModel` that ties everything together |
| `ContentView.swift` | Watch | Start/Stop, status, metronome toggles |
| `WorkoutManager.swift` | Watch | HealthKit workout session (keeps sensors at full rate) + heart rate |
| `MotionStreamer.swift` | Watch | 100 Hz deviceMotion → 20-sample batches |
| `CPRPacket.swift` | Watch | CPR1 binary encoder (tested against the Python decoder) |
| `Metronome.swift` | Watch | Haptic metronome, optional every-other-beat |
| `PhoneLink.swift` | Watch | WatchConnectivity to the phone |
| `CPRCoachApp.swift` | iOS | App entry + `RelayModel` |
| `ContentView.swift` | iOS | Laptop address, status, traffic, watch controls |
| `WatchLink.swift` | iOS | WatchConnectivity → ordered frames for the laptop |
| `LaptopSocket.swift` | iOS | WebSocket to `/ingest`: hello, ping, reconnect with backoff |
