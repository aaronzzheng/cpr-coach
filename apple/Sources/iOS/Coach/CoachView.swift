// Phone coach screen — same design language as the laptop dashboard: true black, borderless
// graphite surfaces, white numbers (colour only on marks), and status always as icon + words.
// The instruction is the hero; numbers scale to fit rather than truncate.
import AVFoundation
import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

enum Palette {
    static let ink = Color.black
    static let surface1 = Color(hex: 0x1C1C1E)
    static let surface2 = Color(hex: 0x2C2C2E)
    static let text = Color(hex: 0xF5F5F7)
    static let muted = Color(hex: 0xA1A1A6)
    static let faint = Color(hex: 0x6E6E73)
    static let accent = Color(hex: 0xFF375F)
    static let good = Color(hex: 0x30D158)
    static let warn = Color(hex: 0xFF9F0A)
    static let urgent = Color(hex: 0xFF453A)
    static let swap = Color(hex: 0xBF5AF2)

    static func tone(_ t: CoachTone) -> Color {
        switch t {
        case .urgent: urgent
        case .warning: warn
        case .swap: swap
        case .good: good
        }
    }

    static func symbol(_ t: CoachTone) -> String {
        switch t {
        case .urgent: "exclamationmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .swap: "arrow.triangle.2.circlepath"
        case .good: "checkmark.circle.fill"
        }
    }
}

private let cardShape = RoundedRectangle(cornerRadius: 22, style: .continuous)

// MARK: Screen

struct CoachView: View {
    @Environment(CoachModel.self) private var coach

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            ZStack {
                Palette.ink.ignoresSafeArea()
                VStack(spacing: 12) {
                    TopBar()
                    if landscape {
                        HStack(spacing: 12) {
                            CameraCard()
                            VStack(spacing: 12) { lowerContent(compact: true) }
                                .frame(width: min(380, geo.size.width * 0.4))
                        }
                    } else {
                        CameraCard()
                        lowerContent(compact: false)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                if coach.phase == .summary, let s = coach.summary { SummarySheet(summary: s) }
            }
        }
        .preferredColorScheme(.dark)
        .task { await coach.startCamera() }
    }

    @ViewBuilder
    private func lowerContent(compact: Bool) -> some View {
        switch coach.phase {
        case .setup, .summary:
            SetupCard()
        case .countdown, .running:
            InstructionCard()
            HStack(spacing: 12) {
                MetricTile(label: "Rate", value: coach.live.rateCpm, digits: 0, unit: "/min",
                           scale: (80, 140), target: (Targets.rateMin, Targets.rateMax),
                           outWords: ("Too slow", "Too fast"), source: coach.live.rateSource?.rawValue, estimate: false)
                MetricTile(label: "Depth", value: coach.live.depthCm, digits: 1, unit: "cm",
                           scale: (0, 8), target: (Targets.depthMin, Targets.depthMax),
                           outWords: ("Too shallow", "Too deep"),
                           source: coach.live.depthCm == nil ? nil : (coach.live.depthEstimate ? "camera" : "watch"),
                           estimate: coach.live.depthEstimate)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: Top bar

private struct TopBar: View {
    @Environment(CoachModel.self) private var coach

    var body: some View {
        HStack(spacing: 16) {
            SourceDot(label: "Watch", on: coach.watchStreaming)
            SourceDot(label: "Arm in view", on: coach.posture?.visible == true)
            Spacer(minLength: 0)
            if let hr = coach.live.heartRate {
                Label("\(Int(hr))", systemImage: "heart.fill")
                    .font(.headline.monospacedDigit())
                    .labelStyle(TintedIconLabel(tint: Palette.accent))
                    .accessibilityLabel("Heart rate \(Int(hr))")
            }
            if coach.phase == .running {
                Text(clock(coach.elapsed))
                    .font(.system(.title3, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Palette.text)
            }
        }
        .frame(height: 36)
    }
}

private struct SourceDot: View {
    let label: String
    let on: Bool
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(on ? Palette.good : .clear)
                .overlay(Circle().strokeBorder(on ? .clear : Palette.faint, lineWidth: 1.5))
                .frame(width: 7, height: 7)
            Text(label).font(.footnote.weight(.medium))
        }
        .foregroundStyle(on ? Palette.muted : Palette.faint)
        .accessibilityElement(children: .combine)
        .accessibilityValue(on ? "connected" : "not connected")
    }
}

private struct TintedIconLabel: LabelStyle {
    let tint: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.foregroundStyle(tint).font(.subheadline)
            configuration.title.foregroundStyle(Palette.text)
        }
    }
}

// MARK: Camera

private struct CameraCard: View {
    @Environment(CoachModel.self) private var coach

    var body: some View {
        ZStack {
            Palette.surface1
            if coach.cameraStatus == .running {
                CameraPreview(layer: coach.camera.previewLayer)
                SkeletonOverlay(posture: coach.posture, imageSize: coach.poseImageSize)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: coach.cameraStatus == .denied ? "video.slash" : "video").font(.title2)
                    Text(coach.cameraStatus == .denied ? "Camera access is off" : "Starting camera")
                        .font(.headline).foregroundStyle(Palette.text)
                    if coach.cameraStatus == .denied {
                        Text("Turn it on in Settings › CPR Coach for posture coaching.")
                            .font(.subheadline).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
                    }
                }
                .foregroundStyle(Palette.faint)
                .padding(24)
            }
            if case .countdown(let n) = coach.phase {
                Text("\(n)")
                    .font(.system(size: 150, weight: .bold))
                    .tracking(-6)
                    .foregroundStyle(Palette.text)
                    .contentTransition(.numericText(countsDown: true))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial)
                    .onTapGesture { coach.stop() }
            }
            if coach.phase == .running {
                VStack {
                    HStack(spacing: 10) {
                        Spacer()
                        RunningControls()
                    }
                    Spacer()
                }
                .padding(12)
            }
        }
        .clipShape(cardShape)
        .frame(maxHeight: .infinity)
    }
}

private struct RunningControls: View {
    @Environment(CoachModel.self) private var coach

    var body: some View {
        @Bindable var coach = coach
        HStack(spacing: 10) {
            GlassButton(symbol: "metronome.fill", on: coach.metronomeOn, label: "Metronome") { coach.metronomeOn.toggle() }
            GlassButton(symbol: coach.muted ? "speaker.slash.fill" : "speaker.wave.2.fill", on: !coach.muted, label: "Voice coach") {
                coach.muted.toggle()
            }
            Button { coach.stop() } label: {
                Text("Stop")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .frame(height: 44)
                    .background(Palette.urgent, in: Capsule())
            }
            .accessibilityHint("Ends the session and shows your score")
        }
    }
}

private struct GlassButton: View {
    let symbol: String
    let on: Bool
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(on ? Palette.text : Palette.faint)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
        }
        .accessibilityLabel(label)
        .accessibilityValue(on ? "on" : "off")
    }
}

// MARK: Instruction (hero)

private struct InstructionCard: View {
    @Environment(CoachModel.self) private var coach

    var body: some View {
        let rule = coach.phase == .running ? coach.banner : nil
        let title = rule?.banner ?? (coach.phase == .running ? "Keep going" : "Get ready")
        let detail = coach.phase == .running ? instructionDetail(rule?.id, coach.live) : nil
        HStack(spacing: 14) {
            if let rule {
                Image(systemName: Palette.symbol(rule.tone))
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Palette.tone(rule.tone))
                    .frame(width: 54, height: 54)
                    .background(Palette.tone(rule.tone).opacity(0.2), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 34, weight: .bold))
                    .tracking(-0.8)
                    .foregroundStyle(rule == nil ? Palette.muted : Palette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let detail {
                    Text(detail).font(.subheadline).foregroundStyle(Palette.muted).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .background {
            ZStack {
                Palette.surface1
                if let rule { Palette.tone(rule.tone).opacity(rule.tone == .urgent || rule.tone == .swap ? 0.2 : 0.14) }
            }
            .clipShape(cardShape)
        }
        .animation(.smooth(duration: 0.25), value: title)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// One line of specifics under the instruction, from the live numbers (mirrors the dashboard).
func instructionDetail(_ ruleId: String?, _ l: LiveState) -> String? {
    let rate = l.rateCpm.map { Int($0.rounded()) }
    let depth = l.depthCm.map { (l.depthEstimate ? "≈" : "") + String(format: "%.1f cm", $0) }
    switch ruleId {
    case "too_shallow", "too_deep": return depth.map { "Depth \($0). Aim for 5–6 cm." }
    case "too_slow", "too_fast": return rate.map { "\($0) per minute. Aim for 100–120, follow the beat." }
    case "elbows_bent": return l.elbowAngleDeg.map { "Elbows at \(Int($0.rounded()))°. Straighten your arms." }
    case "not_over_hands": return "Lean forward so your shoulders are above your hands."
    case "swap": return "Hand over to the next person without pausing."
    case "no_compressions": return "Every second without compressions counts."
    default:
        guard let rate else { return nil }
        return depth.map { "\(rate) per minute at \($0)." } ?? "\(rate) per minute."
    }
}

// MARK: Stat tile

private struct MetricTile: View {
    let label: String
    let value: Double?
    let digits: Int
    let unit: String
    let scale: (Double, Double)
    let target: (Double, Double)
    let outWords: (String, String)
    let source: String?
    let estimate: Bool

    private enum State { case none, estimate, low, ok, high }
    private var state: State {
        guard let v = value else { return .none }
        if estimate { return .estimate }
        return v < target.0 ? .low : v > target.1 ? .high : .ok
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(label).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.muted)
                Spacer(minLength: 0)
                chip
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value.map { (estimate ? "≈" : "") + String(format: "%.\(digits)f", $0) } ?? "—")
                    .font(.system(size: 52, weight: .semibold))
                    .tracking(-1.5)
                    .foregroundStyle(value == nil ? Palette.faint : Palette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: value.map { ($0 * pow(10, Double(digits))).rounded() })
                Text(unit).font(.headline.weight(.medium)).foregroundStyle(Palette.muted).fixedSize()
            }
            Meter(value: value, scale: scale, target: target, fill: fillColor)
            HStack {
                Text("Target \(fmt(target.0))–\(fmt(target.1))")
                Spacer(minLength: 4)
                Text(source.map { $0.capitalized + (estimate ? " est." : "") } ?? "No data")
            }
            .font(.caption)
            .foregroundStyle(Palette.faint)
            .lineLimit(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface1, in: cardShape)
        .accessibilityElement(children: .combine)
    }

    private var fillColor: Color {
        switch state {
        case .ok: Palette.good
        case .low, .high: Palette.warn
        case .none, .estimate: Palette.faint
        }
    }

    @ViewBuilder private var chip: some View {
        switch state {
        case .none: EmptyView()
        case .estimate: StatusChip(symbol: "camera.fill", text: "Estimate", tint: Palette.muted)
        case .ok: StatusChip(symbol: "checkmark.circle.fill", text: "On target", tint: Palette.good)
        case .low: StatusChip(symbol: "exclamationmark.triangle.fill", text: outWords.0, tint: Palette.warn)
        case .high: StatusChip(symbol: "exclamationmark.triangle.fill", text: outWords.1, tint: Palette.warn)
        }
    }

    private func fmt(_ x: Double) -> String { x == x.rounded() ? String(Int(x)) : String(format: "%.1f", x) }
}

/// Icon + words; collapses to the icon alone (still labelled for VoiceOver) when the tile is narrow.
private struct StatusChip: View {
    let symbol: String
    let text: String
    let tint: Color
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) {
                Image(systemName: symbol).foregroundStyle(tint)
                Text(text).foregroundStyle(Palette.text)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(tint.opacity(0.16), in: Capsule())
            Image(systemName: symbol).foregroundStyle(tint)
                .padding(5)
                .background(tint.opacity(0.16), in: Circle())
        }
        .font(.caption.weight(.semibold))
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

private struct Meter: View {
    let value: Double?
    let scale: (Double, Double)
    let target: (Double, Double)
    let fill: Color

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let x = { (v: Double) in w * (min(scale.1, max(scale.0, v)) - scale.0) / (scale.1 - scale.0) }
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.surface2).frame(height: 8)
                Rectangle().fill(Palette.good.opacity(0.3))
                    .frame(width: x(target.1) - x(target.0), height: 8)
                    .offset(x: x(target.0))
                if let v = value {
                    Capsule().fill(fill).frame(width: max(8, x(v)), height: 8)
                    Circle().fill(Palette.text)
                        .overlay(Circle().strokeBorder(Palette.surface1, lineWidth: 3))
                        .frame(width: 16, height: 16)
                        .offset(x: x(v) - 8)
                }
            }
            .frame(height: 16)
            .animation(.smooth(duration: 0.35), value: value)
        }
        .frame(height: 16)
        .accessibilityHidden(true)
    }
}

// MARK: Setup

private struct SetupCard: View {
    @Environment(CoachModel.self) private var coach

    var body: some View {
        @Bindable var coach = coach
        VStack(alignment: .leading, spacing: 14) {
            Text("Ready to practice").font(.system(size: 28, weight: .bold)).tracking(-0.6)
            Text("Prop the phone up beside you so the camera sees you from the side, arms down to the chest.")
                .font(.subheadline).foregroundStyle(Palette.muted)
            VStack(alignment: .leading, spacing: 8) {
                Check(done: coach.posture?.visible == true, text: "Shoulder, elbow and wrist in view")
                Check(done: coach.watchStreaming, text: "Watch connected (adds depth)")
            }
            HStack(spacing: 10) {
                PillToggle(symbol: "metronome.fill", text: "Metronome", on: $coach.metronomeOn)
                PillToggle(symbol: "speaker.wave.2.fill", text: "Voice", on: Binding(get: { !coach.muted }, set: { coach.muted = !$0 }))
            }
            Button { coach.start() } label: {
                Label("Start session", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .foregroundStyle(.white)
                    .background(Palette.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            Text("Training tool, not a medical device. In an emergency, call your local emergency number first.")
                .font(.caption).foregroundStyle(Palette.faint)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface1, in: cardShape)
    }
}

private struct Check: View {
    let done: Bool
    let text: String
    var body: some View {
        Label {
            Text(text).foregroundStyle(done ? Palette.text : Palette.muted)
        } icon: {
            Image(systemName: done ? "checkmark.circle.fill" : "circle.dashed").foregroundStyle(done ? Palette.good : Palette.faint)
        }
        .font(.subheadline)
    }
}

private struct PillToggle: View {
    let symbol: String
    let text: String
    @Binding var on: Bool
    var body: some View {
        Button { on.toggle() } label: {
            Label(text, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(on ? Palette.text : Palette.faint)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(on ? Palette.surface2 : .clear, in: Capsule())
                .overlay(Capsule().strokeBorder(on ? .clear : Palette.surface2, lineWidth: 1.5))
        }
        .accessibilityValue(on ? "on" : "off")
    }
}

// MARK: Summary

private struct SummarySheet: View {
    @Environment(CoachModel.self) private var coach
    let summary: SessionSummary

    var body: some View {
        let s = summary
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Session score").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.muted)
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text("\(Int(s.score.rounded()))").font(.system(size: 88, weight: .bold)).tracking(-4)
                                Text("/100").font(.title2.weight(.semibold)).foregroundStyle(Palette.faint)
                            }
                            Text("\(s.compressions) compressions in \(clock(s.elapsed))")
                                .font(.subheadline).foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        Text(s.grade)
                            .font(.system(size: 44, weight: .bold))
                            .foregroundStyle(gradeColor)
                            .frame(width: 76, height: 76)
                            .background(gradeColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .accessibilityLabel("Grade \(s.grade)")
                    }
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible())], alignment: .leading, spacing: 18) {
                        Stat(label: "Rate in range", value: pct(s.ratePct), good: s.ratePct.map { $0 >= 0.8 })
                        Stat(label: s.depthEstimated ? "Depth in range (est.)" : "Depth in range", value: pct(s.depthPct), good: s.depthPct.map { $0 >= 0.8 })
                        Stat(label: "Hands on chest", value: pct(s.ccf), good: s.ccf.map { $0 >= 0.8 })
                        Stat(label: "Pauses", value: s.pauses == 0 ? "None" : "\(s.pauses)", good: s.pauses == 0)
                        Stat(label: "Average rate", value: s.avgRate.map { "\(Int($0.rounded())) /min" } ?? "—", good: nil)
                        Stat(label: "Average depth", value: s.avgDepth.map { (s.depthEstimated ? "≈" : "") + String(format: "%.1f cm", $0) } ?? "—", good: nil)
                        Stat(label: "Elbows locked", value: pct(s.elbowPct), good: s.elbowPct.map { $0 >= 0.8 })
                        Stat(label: "Shoulders over hands", value: pct(s.alignPct), good: s.alignPct.map { $0 >= 0.8 })
                    }
                    HStack(spacing: 12) {
                        Button { coach.backToSetup() } label: {
                            Text("Done").frame(maxWidth: .infinity, minHeight: 52)
                                .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        Button { coach.start() } label: {
                            Label("Go again", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity, minHeight: 52)
                                .background(Palette.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                }
                .padding(24)
                .background(Palette.surface1, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .padding(16)
                .frame(maxWidth: 560)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
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

private struct Stat: View {
    let label: String
    let value: String
    let good: Bool?
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(Palette.faint)
            HStack(spacing: 6) {
                if let good {
                    Image(systemName: good ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(good ? Palette.good : Palette.warn)
                        .font(.subheadline)
                }
                Text(value).font(.system(.title3, weight: .semibold)).foregroundStyle(Palette.text)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private func clock(_ s: Double) -> String {
    let t = max(0, Int(s))
    return String(format: "%02d:%02d", t / 60, t % 60)
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

/// Draws the tracked arm over the preview. The preview uses aspect-fill (and is mirrored like the
/// analysed frames), so image pixels map to view points with the same fill scale and centring.
struct SkeletonOverlay: View {
    let posture: PostureFrame?
    let imageSize: CGSize

    var body: some View {
        Canvas { ctx, size in
            guard let p = posture, p.visible, let j = p.joints, imageSize.width > 0 else { return }
            let scale = max(size.width / imageSize.width, size.height / imageSize.height)
            let origin = CGPoint(x: (size.width - imageSize.width * scale) / 2, y: (size.height - imageSize.height * scale) / 2)
            func map(_ q: CGPoint) -> CGPoint { CGPoint(x: origin.x + q.x * scale, y: origin.y + q.y * scale) }
            let s = map(j.shoulder), e = map(j.elbow), w = map(j.wrist)
            let tone = p.elbowsLocked == true && p.aligned == true ? Palette.good : Palette.warn

            var vertical = Path()
            vertical.move(to: s)
            vertical.addLine(to: CGPoint(x: s.x, y: w.y))
            ctx.stroke(vertical, with: .color(Palette.text.opacity(0.35)), lineWidth: 2)

            var arm = Path()
            arm.move(to: s); arm.addLine(to: e); arm.addLine(to: w)
            ctx.stroke(arm, with: .color(tone), style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
            for pt in [s, e, w] {
                let r = CGRect(x: pt.x - 7, y: pt.y - 7, width: 14, height: 14)
                ctx.fill(Path(ellipseIn: r), with: .color(Palette.text))
                ctx.stroke(Path(ellipseIn: r), with: .color(.black), lineWidth: 2.5)
            }
            if let a = p.elbowAngleDeg {
                let label = ctx.resolve(Text("\(Int(a.rounded()))°").font(.system(.headline, weight: .semibold)).foregroundStyle(Palette.text))
                let ts = label.measure(in: size)
                let box = CGRect(x: e.x + 18, y: e.y - ts.height / 2 - 6, width: ts.width + 18, height: ts.height + 12)
                ctx.fill(Path(roundedRect: box, cornerRadius: 10), with: .color(.black.opacity(0.6)))
                ctx.draw(label, at: CGPoint(x: box.midX, y: box.midY))
            }
        }
        .allowsHitTesting(false)
    }
}
