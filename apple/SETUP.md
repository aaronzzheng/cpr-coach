# Apple setup (human steps)

All the Swift code is already written. You need to do the parts that require Xcode clicks,
your Apple ID, and the physical devices. **Do steps 1–3 early — the first watch install can take 5–15 minutes.**

Everything else (dashboard, backend, simulator) works without any of this.

Your hardware: **Apple Watch Series 5 (A2157) → max watchOS 10**, so the watch target must be **watchOS 10.0**.
Your Xcode 27 can still target watchOS 10 (its watchOS SDK supports deployment back to 9.0).

---

## 1. One-time Mac setup (≈5 min)

1. Install XcodeGen, which generates the Xcode project from `apple/project.yml`:

   ```bash
   brew install xcodegen
   ```

2. **Xcode → Settings… → Accounts → +** → sign in with your Apple ID (a free one works). Your *Personal Team* appears in the list.
3. Find your team ID: in that Accounts pane select the team; or run

   ```bash
   defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier | grep -E "teamID|teamName"
   ```

4. Save your signing settings (the prefix must be unique to you, e.g. your GitHub name):

   ```bash
   make apple-signing TEAM=<your team ID> PREFIX=com.yourname
   ```

   This writes `apple/Config/Local.xcconfig`, which is git-ignored, so each teammate keeps their own.

Everything else (watchOS 10.0 target for the Series 5, HealthKit, Workout background mode, every Info.plist permission string, App Transport Security for `ws://`) is already in `project.yml`.
To open the project in Xcode: `make apple-project && open apple/CPRCoach.xcodeproj`.

## 2. Phone and watch (≈10–20 min, mostly waiting)

1. **iPhone:** Settings → Privacy & Security → **Developer Mode** → on → restart → confirm.
2. Connect the iPhone to the Mac with a cable, unlock it and tap **Trust**.
3. Build, sign and install (the watch app is embedded in the iPhone app):

   ```bash
   make apple-install
   ```

   The first time, iPhone → Settings → General → **VPN & Device Management** → your Apple ID → **Trust**.
4. **Watch:** keep it on its charger, near the phone, unlocked. On the iPhone open the **Watch** app → *My Watch* → scroll to **CPR Coach** → **Install** (if it didn't install automatically).
5. **Watch:** Settings → Privacy & Security → **Developer Mode** → on, if it asks (the watch restarts).

## 3. Connect everything

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
| Watch app never installs | Mac and iPhone on the same network (the hotspot trick works here too), watch unlocked and on its charger, and **Window → Devices and Simulators → watch → Unpair/Re-pair in Xcode** as a last resort. |
| "Could not launch… untrusted developer" | iPhone → Settings → General → VPN & Device Management → Trust. |
| `make apple-install`: signing / provisioning error | Check `apple/Config/Local.xcconfig` has your team ID, and that the prefix is unique (free teams can't reuse a bundle ID someone else registered). If HealthKit is refused for your account, delete the two `com.apple.developer.healthkit*` lines in `project.yml` and run again. |
| Watch haptic metronome misses beats | Turn on **Haptic every 2 beats** on the watch. The laptop's audio metronome is the primary one. |
| Depth reads too high or low | Expected before calibration (M4). The ruler calibration fixes the scale. |
| App stops working after 7 days | Free-account builds expire. Run from Xcode again. |

## What's in the code

| File | Target | Role |
|---|---|---|
| `project.yml` | both | XcodeGen spec: targets, deployment versions, capabilities, Info.plist keys |
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
