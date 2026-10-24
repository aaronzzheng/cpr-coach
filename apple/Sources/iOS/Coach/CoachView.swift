// Phone coach screen. Monitor-style: true black, big tabular numerals, colour only for signal
// (green in range, amber adjust, red act now, violet swap). The live instruction is the hero:
// a rescuer mid-compression can only glance, so it's the largest thing on screen.
import AVFoundation
import SwiftUI

enum Palette {
    static let ink = Color.black
    static let panel = Color(red: 0.063, green: 0.078, blue: 0.094)      // #101418
    static let line = Color(red: 0.137, green: 0.165, blue: 0.192)       // #232A31
    static let text = Color(red: 0.949, green: 0.961, blue: 0.969)       // #F2F5F7
    static let muted = Color(red: 0.541, green: 0.588, blue: 0.639)      // #8A96A3
    static let good = Color(red: 0.239, green: 0.863, blue: 0.518)       // #3DDC84 trace green
    static let warn = Color(red: 1.0, green: 0.690, blue: 0.125)         // #FFB020
    static let urgent = Color(red: 1.0, green: 0.302, blue: 0.302)       // #FF4D4D
    static let swap = Color(red: 0.706, green: 0.549, blue: 1.0)         // #B48CFF

    static func tone(_ t: CoachTone) -> Color {
        switch t {
        case .urgent: urgent
        case .warning: warn
        case .swap: swap
        case .good: good
        }
    }
}

struct CoachView: View {
    @Environment(CoachModel.self) private var coach

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            ZStack {
                Palette.ink.ignoresSafeArea()
                if landscape {
                    HStack(spacing: 12) {
                        cameraPane
                        VStack(spacing: 12) {
                            statusBar
                            readouts(vertical: true)
                        }
                        .frame(width: min(300, geo.size.width * 0.32))
                    }
                    .safeAreaInset(edge: .bottom) { instruction.padding(.top, 12) }
                    .padding(12)
                } else {
                    VStack(spacing: 12) {
                        statusBar
                        cameraPane
                        readouts(vertical: false).frame(height: 150)
                        instruction
                    }
                    .padding(12)
                }
                overlays
            }
        }
        .preferredColorScheme(.dark)
        .task { await coach.startCamera() }
    }

    // MARK: Panes

    private var cameraPane: some View {
        ZStack {
            Palette.panel
            if coach.cameraStatus == .running {
                CameraPreview(layer: coach.camera.previewLayer)
                SkeletonOverlay(posture: coach.posture, imageSize: coach.poseImageSize)
            } else {
                Text(cameraMessage)
                    .font(.callout)
                    .foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var cameraMessage: String {
        switch coach.cameraStatus {
        case .denied: "Camera access is off. Turn it on in Settings › CPR Coach to get posture coaching."
        case .unavailable: "No front camera available."
        default: "Starting camera…"
        }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            StatusChip(label: "Watch", on: coach.watchStreaming)
            StatusChip(label: "Arm in view", on: coach.posture?.visible == true)
            if let hr = coach.live.heartRate {
                Text("♥ \(Int(hr))").font(.callout.monospacedDigit()).foregroundStyle(Palette.text)
            }
            Spacer(minLength: 0)
            if coach.phase == .running {
                Text(clock(coach.elapsed))
                    .font(.system(.title3, design: .rounded).weight(.semibold).monospacedDigit())
                    .foregroundStyle(Palette.text)
            }
        }
    }

    @ViewBuilder
    private func readouts(vertical: Bool) -> some View {
        let layout = vertical ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
        layout {
            RateReadout(rate: coach.live.rateCpm, source: coach.live.rateSource)
            DepthReadout(depth: coach.live.depthCm, estimate: coach.live.depthEstimate)
        }
    }

    private var instruction: some View {
        let rule = coach.phase == .running ? coach.banner : nil
        let text: String = {
            if let rule { return rule.banner }
            switch coach.phase {
            case .running: return "Keep going"
            case .countdown: return "Get ready"
            default: return "Ready when you are"
            }
        }()
        return Text(text)
            .font(.system(size: 44, weight: .heavy, design: .rounded))
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .foregroundStyle(rule.map { $0.tone == .warning || $0.tone == .good ? Palette.ink : Palette.text } ?? Palette.muted)
            .frame(maxWidth: .infinity, minHeight: 84)
            .background(rule.map { Palette.tone($0.tone) } ?? Palette.panel, in: RoundedRectangle(cornerRadius: 14))
            .contentTransition(.opacity)
            .animation(.easeOut(duration: 0.2), value: text)
            .accessibilityAddTraits(.updatesFrequently)
    }

    @ViewBuilder
    private var overlays: some View {
        switch coach.phase {
        case .setup:
            SetupPanel()
        case .countdown(let n):
            Text("\(n)")
                .font(.system(size: 160, weight: .heavy, design: .rounded))
                .foregroundStyle(Palette.text)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black.opacity(0.55))
                .onTapGesture { coach.stop() }
        case .running:
            VStack {
                HStack {
                    Spacer()
                    RunningControls()
                }
                Spacer()
            }
            .padding(.top, 52)
            .padding(.horizontal, 20)
        case .summary:
            if let s = coach.summary { SummaryPanel(summary: s) }
        }
    }
}

private func clock(_ s: Double) -> String {
    let t = max(0, Int(s))
    return String(format: "%02d:%02d", t / 60, t % 60)
}

// MARK: Pieces

struct StatusChip: View {
    let label: String
    let on: Bool
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(on ? Palette.good : Palette.muted.opacity(0.6)).frame(width: 8, height: 8)
            Text(label).font(.callout)
        }
        .foregroundStyle(on ? Palette.text : Palette.muted)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Palette.panel, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityValue(on ? "on" : "off")
    }
}

struct RateReadout: View {
    let rate: Double?
    let source: RateSource?
    var body: some View {
        let inRange = rate.map { $0 >= Targets.rateMin && $0 <= Targets.rateMax }
        VStack(alignment: .leading, spacing: 2) {
            Text("Rate").font(.callout).foregroundStyle(Palette.muted)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(rate.map { "\(Int($0.rounded()))" } ?? "—")
                    .font(.system(size: 64, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(inRange == nil ? Palette.muted : inRange! ? Palette.good : Palette.warn)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: rate.map { Int($0.rounded()) })
                Text("/min").font(.title3).foregroundStyle(Palette.muted)
            }
            Text(source.map { "Target 100–120 · via \($0.rawValue)" } ?? "Target 100–120")
                .font(.footnote).foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(14)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct DepthReadout: View {
    let depth: Double?
    let estimate: Bool
    private let maxCm = 8.0
    var body: some View {
        let inBand = depth.map { $0 >= Targets.depthMin && $0 <= Targets.depthMax }
        let color = inBand == nil ? Palette.muted : inBand! ? Palette.good : Palette.warn
        HStack(spacing: 14) {
            // Fills downward like the chest; green band = 5–6 cm.
            GeometryReader { g in
                let h = g.size.height
                ZStack(alignment: .top) {
                    Capsule().fill(Palette.line)
                    Rectangle().fill(Palette.good.opacity(0.28))
                        .frame(height: h * (Targets.depthMax - Targets.depthMin) / maxCm)
                        .offset(y: h * Targets.depthMin / maxCm)
                    if let d = depth {
                        Capsule().fill(color).frame(height: h * min(d, maxCm) / maxCm)
                            .animation(.snappy, value: d)
                    }
                }
            }
            .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Depth").font(.callout).foregroundStyle(Palette.muted)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(depth.map { (estimate ? "~" : "") + String(format: "%.1f", $0) } ?? "—")
                        .font(.system(size: 52, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundStyle(color)
                    Text("cm").font(.title3).foregroundStyle(Palette.muted)
                }
                Text(estimate ? "Target 5–6 · camera estimate" : "Target 5–6")
                    .font(.footnote).foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(14)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct RunningControls: View {
    @Environment(CoachModel.self) private var coach
    var body: some View {
        @Bindable var coach = coach
        HStack(spacing: 10) {
            Button { coach.metronomeOn.toggle() } label: {
                Image(systemName: coach.metronomeOn ? "metronome.fill" : "metronome")
            }
            .accessibilityLabel(coach.metronomeOn ? "Metronome on" : "Metronome off")
            Button { coach.muted.toggle() } label: {
                Image(systemName: coach.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
            }
            .accessibilityLabel(coach.muted ? "Voice muted" : "Voice on")
            Button("Stop") { coach.stop() }
                .font(.headline)
                .padding(.horizontal, 6)
        }
        .buttonStyle(.bordered)
        .tint(Palette.text)
    }
}

struct SetupPanel: View {
    @Environment(CoachModel.self) private var coach
    var body: some View {
        @Bindable var coach = coach
        VStack(alignment: .leading, spacing: 14) {
            Text("CPR Coach").font(.largeTitle.weight(.heavy))
            Text("Prop the phone up beside the person so the camera sees you from the side, kneeling, arms down to the chest.")
                .foregroundStyle(Palette.muted)
            VStack(alignment: .leading, spacing: 8) {
                StepRow(done: coach.posture?.visible == true, text: "Camera can see your shoulder, elbow and wrist")
                StepRow(done: coach.watchStreaming, text: "Watch connected (optional: adds depth)")
            }
            HStack {
                Toggle("Metronome", isOn: $coach.metronomeOn)
                Toggle("Voice", isOn: Binding(get: { !coach.muted }, set: { coach.muted = !$0 }))
            }
            .tint(Palette.good)
            Button { coach.start() } label: {
                Text("Start").font(.title2.weight(.heavy)).frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.good)
            .foregroundStyle(Palette.ink)
            Text("Training tool — not a medical device. In a real emergency, call your local emergency number first.")
                .font(.footnote).foregroundStyle(Palette.muted)
        }
        .padding(22)
        .frame(maxWidth: 520)
        .background(.ultraThinMaterial.opacity(0.9), in: RoundedRectangle(cornerRadius: 20))
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}

struct StepRow: View {
    let done: Bool
    let text: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(done ? Palette.good : Palette.muted)
            Text(text).foregroundStyle(done ? Palette.text : Palette.muted)
        }
        .font(.callout)
    }
}

struct SummaryPanel: View {
    @Environment(CoachModel.self) private var coach
    let summary: SessionSummary

    var body: some View {
        let s = summary
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text("\(Int(s.score.rounded()))")
                        .font(.system(size: 88, weight: .heavy, design: .rounded).monospacedDigit())
                    VStack(alignment: .leading) {
                        Text("Grade \(s.grade)").font(.title2.weight(.bold)).foregroundStyle(gradeColor)
                        Text("\(s.compressions) compressions in \(clock(s.elapsed))").foregroundStyle(Palette.muted)
                    }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                    Stat(label: "Rate in range", value: pct(s.ratePct), good: s.ratePct.map { $0 >= 0.8 })
                    Stat(label: s.depthEstimated ? "Depth in range (est.)" : "Depth in range", value: pct(s.depthPct), good: s.depthPct.map { $0 >= 0.8 })
                    Stat(label: "Hands on chest", value: pct(s.ccf), good: s.ccf.map { $0 >= 0.8 })
                    Stat(label: "Elbows locked", value: pct(s.elbowPct), good: s.elbowPct.map { $0 >= 0.8 })
                    Stat(label: "Shoulders over hands", value: pct(s.alignPct), good: s.alignPct.map { $0 >= 0.8 })
                    Stat(label: "Average rate", value: s.avgRate.map { "\(Int($0.rounded()))/min" } ?? "—", good: nil)
                    Stat(label: "Average depth", value: s.avgDepth.map { String(format: "%@%.1f cm", s.depthEstimated ? "~" : "", $0) } ?? "—", good: nil)
                    Stat(label: "Pauses", value: s.pauses == 0 ? "None" : "\(s.pauses), longest \(String(format: "%.1f", s.longestPause)) s", good: s.pauses == 0)
                }
                HStack(spacing: 12) {
                    Button { coach.start() } label: { Text("Go again").frame(maxWidth: .infinity, minHeight: 48) }
                        .buttonStyle(.borderedProminent).tint(Palette.good).foregroundStyle(Palette.ink)
                    Button { coach.backToSetup() } label: { Text("Done").frame(maxWidth: .infinity, minHeight: 48) }
                        .buttonStyle(.bordered).tint(Palette.text)
                }
                .font(.headline)
            }
            .padding(22)
        }
        .frame(maxWidth: 620)
        .background(Palette.panel.opacity(0.97), in: RoundedRectangle(cornerRadius: 20))
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.6))
    }

    private var gradeColor: Color {
        switch summary.grade {
        case "A", "B": Palette.good
        case "C": Palette.warn
        default: Palette.urgent
        }
    }

    private func pct(_ x: Double?) -> String { x.map { "\(Int(($0 * 100).rounded()))%" } ?? "—" }
}

struct Stat: View {
    let label: String
    let value: String
    let good: Bool?
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.bold).monospacedDigit())
                .foregroundStyle(good == nil ? Palette.text : good! ? Palette.good : Palette.warn)
            Text(label).font(.footnote).foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Palette.ink.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: Camera preview + skeleton

struct CameraPreview: UIViewRepresentable {
    let layer: AVCaptureVideoPreviewLayer

    func makeUIView(context: Context) -> PreviewHost {
        let v = PreviewHost()
        v.previewLayer = layer
        v.layer.addSublayer(layer)
        return v
    }

    func updateUIView(_ uiView: PreviewHost, context: Context) {}

    final class PreviewHost: UIView {
        var previewLayer: AVCaptureVideoPreviewLayer?
        override func layoutSubviews() {
            super.layoutSubviews()
            previewLayer?.frame = bounds
        }
    }
}

/// Draws the tracked arm over the preview. Both use aspect-fit, so the same fitted rect maps
/// image pixels to view points.
struct SkeletonOverlay: View {
    let posture: PostureFrame?
    let imageSize: CGSize

    var body: some View {
        Canvas { ctx, size in
            guard let p = posture, p.visible, let j = p.joints, imageSize.width > 0 else { return }
            let scale = min(size.width / imageSize.width, size.height / imageSize.height)
            let origin = CGPoint(x: (size.width - imageSize.width * scale) / 2, y: (size.height - imageSize.height * scale) / 2)
            func map(_ q: CGPoint) -> CGPoint { CGPoint(x: origin.x + q.x * scale, y: origin.y + q.y * scale) }
            let s = map(j.shoulder), e = map(j.elbow), w = map(j.wrist)
            let ok = p.elbowsLocked == true && p.aligned == true
            let color = ok ? Palette.good : Palette.warn

            var vertical = Path()
            vertical.move(to: s)
            vertical.addLine(to: CGPoint(x: s.x, y: w.y))
            ctx.stroke(vertical, with: .color(color.opacity(0.6)), style: StrokeStyle(lineWidth: 2, dash: [8, 7]))

            var arm = Path()
            arm.move(to: s); arm.addLine(to: e); arm.addLine(to: w)
            ctx.stroke(arm, with: .color(color), style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
            for pt in [s, e, w] {
                ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 6, y: pt.y - 6, width: 12, height: 12)), with: .color(Palette.text))
            }
            if let a = p.elbowAngleDeg {
                ctx.draw(Text("\(Int(a.rounded()))°").font(.system(.title3, design: .rounded).weight(.bold)).foregroundStyle(color),
                         at: CGPoint(x: e.x + 30, y: e.y), anchor: .leading)
            }
        }
        .allowsHitTesting(false)
    }
}
