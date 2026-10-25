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
    @AppStorage("onboarded") private var onboarded = false

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
                            .frame(maxHeight: coach.phase == .setup || coach.phase == .summary ? 230 : .infinity)
                        lowerContent(compact: false)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                if coach.phase == .summary, let s = coach.summary { SummarySheet(summary: s) }
            }
            .id(coach.language) // re-render every string when the language changes
        }
        .simulatedCallOverlay(coach)
        .sheet(isPresented: Bindable(coach).showAEDGuide) { AEDGuideSheet() }
        .fullScreenCover(isPresented: Binding(get: { !onboarded }, set: { onboarded = !$0 })) {
            OnboardingView {
                onboarded = true
                Task { await coach.startCamera() }
            }
        }
        .preferredColorScheme(.dark)
        .task { if onboarded { await coach.startCamera() } }
    }

    @ViewBuilder
    private func lowerContent(compact: Bool) -> some View {
        switch coach.phase {
        case .setup, .summary:
            // The setup card can be taller than the screen (long languages); it scrolls under the camera.
            ScrollView { SetupCard() }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
                .clipShape(cardShape)
        case .countdown, .running:
            InstructionCard()
            HStack(spacing: 12) {
                MetricTile(label: tr("Rate"), value: coach.live.rateCpm, digits: 0, unit: tr("/min"),
                           scale: (80, 140), target: (Targets.rateMin, Targets.rateMax),
                           outWords: (tr("Too slow"), tr("Too fast")), source: coach.live.rateSource.map { tr($0 == .watch ? "Watch" : "Camera") },
                           estimate: false)
                MetricTile(label: tr("Depth"), value: coach.live.depthCm, digits: 1, unit: "cm",
                           scale: (0, 8), target: (Targets.depthMin, Targets.depthMax),
                           outWords: (tr("Too shallow"), tr("Too deep")),
                           source: coach.live.depthSource.map(depthSourceName),
                           estimate: coach.live.depthEstimate, tolerance: Targets.depthToleranceCm)
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
            SourceDot(label: tr("Watch"), on: coach.watchStreaming)
                .onLongPressGesture(minimumDuration: 1) { coach.toggleDemoReplay() }
                .sensoryFeedback(.success, trigger: coach.demoReplayStep)
            SourceDot(label: tr("Arm in view"), on: coach.posture?.visible == true)
            Spacer(minLength: 0)
            if let since = coach.simulatedCallSince, coach.phase == .running {
                Button { coach.endSimulatedCall() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "phone.fill").font(.caption.weight(.bold))
                        Text(CoachModel.emergencyNumber).font(.footnote.weight(.semibold))
                        Text(since, style: .timer).font(.footnote.monospacedDigit())
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(Palette.good, in: Capsule())
                }
                .accessibilityLabel(tr("Calling %@", CoachModel.emergencyNumber))
                .accessibilityHint(tr("End demo call"))
            }
            if coach.listening { ListeningIndicator(heard: coach.heard) }
            if let hr = coach.live.heartRate {
                Label("\(Int(hr))", systemImage: "heart.fill")
                    .font(.headline.monospacedDigit())
                    .labelStyle(TintedIconLabel(tint: Palette.accent))
                    .accessibilityLabel(tr("Heart rate %@", "\(Int(hr))"))
            }
            if coach.phase == .running {
                // Skills check counts down its 2 minutes; otherwise the session clock counts up.
                Text(coach.mode == .skillsCheck ? clock(max(0, SkillsCheck.durationS - coach.elapsed)) : clock(coach.elapsed))
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
        .accessibilityValue(on ? tr("connected") : tr("not connected"))
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
                    Text(coach.cameraStatus == .denied ? tr("Camera access is off") : tr("Starting camera"))
                        .font(.headline).foregroundStyle(Palette.text)
                    if coach.cameraStatus == .denied {
                        Text(tr("Turn it on in Settings › CPR Coach for posture coaching."))
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
            if coach.mode == .emergency {
                GlassButton(symbol: "phone.fill", on: true, label: tr("Call %@", CoachModel.emergencyNumber)) { coach.callEmergency() }
                Button { coach.aedArrived() } label: {
                    Text("AED")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 44)
                        .background(Palette.good.opacity(coach.aedArrivedAt == nil ? 0.9 : 0.5), in: Capsule())
                }
                .accessibilityLabel(tr("The AED is here"))
            }
            GlassButton(symbol: "metronome.fill", on: coach.metronomeOn, label: tr("Metronome")) { coach.metronomeOn.toggle() }
            GlassButton(symbol: coach.muted ? "speaker.slash.fill" : "speaker.wave.2.fill", on: !coach.muted, label: tr("Voice coach")) {
                coach.muted.toggle()
            }
            Button { coach.stop() } label: {
                Text(tr("Stop"))
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .frame(height: 44)
                    .background(Palette.urgent, in: Capsule())
            }
            .accessibilityHint(tr("Ends the session and shows your score"))
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
        .accessibilityValue(on ? tr("on") : tr("off"))
    }
}

// MARK: Instruction (hero)

private struct InstructionCard: View {
    @Environment(CoachModel.self) private var coach

    var body: some View {
        let rule = coach.phase == .running ? coach.banner : nil
        let title = rule.map { tr($0.banner) } ?? (coach.phase == .running ? tr("Keep going") : tr("Get ready"))
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
    let depth = l.depthCm.map { (l.depthEstimate ? "≈" : "") + trNumber($0, digits: 1) + " cm" }
    switch ruleId {
    case "too_shallow", "too_deep":
        return depth.map { tr("Depth %@. Aim for %@ cm.", $0, trNumber(Targets.depthMin, digits: 1) + "–" + trNumber(Targets.depthMax, digits: 1)) }
    case "swap_soon":
        return l.swapInS.map { tr("Depth is trending down: below %@ cm in about %@ s.", trNumber(Targets.depthMin, digits: 1), "\(Int($0.rounded()))") }
    case "breaths": return tr("Tilt the head back, lift the chin, 2 breaths of 1 second each. Then straight back to compressions.")
    case "too_slow", "too_fast": return rate.map { tr("%@ per minute. Aim for 100–120, follow the beat.", "\($0)") }
    case "elbows_bent": return l.elbowAngleDeg.map { tr("Elbows at %@°. Straighten your arms.", "\(Int($0.rounded()))") }
    case "recoil": return tr("Lift your weight off the chest between pushes, but keep your hands on it.")
    case "hands_low": return tr("Your hands are too close to the stomach.")
    case "hands_high": return tr("Your hands are too close to the neck.")
    case "not_over_hands": return tr("Lean forward so your shoulders are above your hands.")
    case "swap": return tr("Hand over to the next person without pausing.")
    case "no_compressions": return tr("Every second without compressions counts.")
    default:
        guard let rate else { return nil }
        return depth.map { tr("%@ per minute at %@.", "\(rate)", $0) } ?? tr("%@ per minute.", "\(rate)")
    }
}

func depthSourceName(_ s: DepthSource) -> String {
    switch s {
    case .fused: tr("Watch + camera")
    case .watch: tr("Watch")
    case .cameraCalibrated: tr("Camera, calibrated")
    case .cameraEstimate: tr("Camera")
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
    /// Slack around the target band before a value counts as out of range.
    var tolerance = 0.0

    private enum State { case none, estimate, low, ok, high }
    private var state: State {
        guard let v = value else { return .none }
        if estimate { return .estimate }
        return v < target.0 - tolerance ? .low : v > target.1 + tolerance ? .high : .ok
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(label).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.muted)
                Spacer(minLength: 0)
                chip
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value.map { (estimate ? "≈" : "") + trNumber($0, digits: digits) } ?? "—")
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
                Text(tr("Target %@", "\(fmt(target.0))–\(fmt(target.1))"))
                Spacer(minLength: 4)
                Text(source ?? tr("No data"))
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
        case .estimate: StatusChip(symbol: "camera.fill", text: tr("Estimate"), tint: Palette.muted)
        case .ok: StatusChip(symbol: "checkmark.circle.fill", text: tr("On target"), tint: Palette.good)
        case .low: StatusChip(symbol: "exclamationmark.triangle.fill", text: outWords.0, tint: Palette.warn)
        case .high: StatusChip(symbol: "exclamationmark.triangle.fill", text: outWords.1, tint: Palette.warn)
        }
    }

    private func fmt(_ x: Double) -> String { x == x.rounded() ? String(Int(x)) : trNumber(x, digits: 1) }
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
            Button { coach.showEmergency = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "staroflife.fill").font(.title3)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(tr("Someone collapsed?")).font(.headline)
                        Text(tr("Call for help and get coached through CPR")).font(.footnote).opacity(0.85)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).opacity(0.7)
                }
                .foregroundStyle(.white)
                .padding(14)
                .background(Palette.urgent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .fullScreenCover(isPresented: $coach.showEmergency) { EmergencySheet().simulatedCallOverlay(coach) }
            HStack(alignment: .firstTextBaseline) {
                Text(tr("Ready to practice")).font(.system(size: 28, weight: .bold)).tracking(-0.6)
                Spacer(minLength: 8)
                LanguageMenu()
            }
            HStack(spacing: 10) {
                Button { coach.start() } label: {
                    Label(tr("Start session"), systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .foregroundStyle(.white)
                        .background(Palette.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                Button { coach.start(skillsCheck: true) } label: {
                    Label(tr("Skills check"), systemImage: "checkmark.seal")
                        .font(.headline)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 54)
                        .foregroundStyle(Palette.text)
                        .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .accessibilityHint(tr("A timed 2-minute test, pass or fail"))
            }
            Text(tr("Prop the phone up beside you so the camera sees you from the side, arms down to the chest."))
                .font(.subheadline).foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                Check(done: coach.posture?.visible == true, text: tr("Shoulder, elbow and wrist in view"))
                Check(done: coach.watchStreaming, text: tr("Watch connected (adds depth)"))
            }
            PatientPicker()
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    PillToggle(symbol: "metronome.fill", text: tr("Metronome"), on: $coach.metronomeOn)
                    PillToggle(symbol: "speaker.wave.2.fill", text: tr("Voice"), on: Binding(get: { !coach.muted }, set: { coach.muted = !$0 }))
                }
                HStack(spacing: 10) {
                    PillToggle(symbol: "mic.fill", text: tr("Hands-free"), on: $coach.handsFree)
                    PillToggle(symbol: "lungs.fill", text: tr("30:2 breaths"), on: $coach.breathsMode)
                }
            }
            if coach.handsFree {
                Text(tr("Say \"swap\", \"how long\", \"how am I doing\" or \"stop\" while you work."))
                    .font(.footnote).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(tr("Training tool, not a medical device. In an emergency, call your local emergency number first."))
                .font(.caption).foregroundStyle(Palette.faint)
                .fixedSize(horizontal: false, vertical: true)
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
        .accessibilityValue(on ? tr("on") : tr("off"))
    }
}

/// Globe menu to switch the coach's language (screen, voice and voice commands) on the spot.
private struct LanguageMenu: View {
    @Environment(CoachModel.self) private var coach
    var body: some View {
        @Bindable var coach = coach
        Menu {
            Picker(tr("Language"), selection: $coach.language) {
                ForEach(AppLanguage.allCases) { Text($0.nativeName).tag($0) }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "globe")
                Text(coach.language.nativeName)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Palette.text)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(Palette.surface2, in: Capsule())
        }
        .accessibilityLabel(tr("Language"))
    }
}

/// Mic + the command just understood, so the rescuer knows they were heard without looking long.
private struct ListeningIndicator: View {
    let heard: String?
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: heard == nil ? "mic.fill" : "checkmark")
                .font(.footnote.weight(.bold))
                .foregroundStyle(heard == nil ? Palette.accent : Palette.good)
                .symbolEffect(.pulse, isActive: heard == nil)
            Text(heard ?? tr("Listening"))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(heard == nil ? Palette.muted : Palette.text)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(Palette.surface1, in: Capsule())
        .animation(.snappy, value: heard)
        .accessibilityElement(children: .combine)
    }
}

/// The spoken emergency check, with buttons for when talking isn't possible.
private struct TriageCard: View {
    @Environment(CoachModel.self) private var coach

    var body: some View {
        if let step = coach.triage {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: coach.listening ? "mic.fill" : "questionmark.circle.fill")
                        .foregroundStyle(Palette.accent)
                        .symbolEffect(.pulse, isActive: coach.listening && coach.triageAwaitingAnswer)
                    Text(coach.listening && coach.triageAwaitingAnswer ? tr("Listening — say yes or no") : tr("Check"))
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.muted)
                    Spacer()
                    if let heard = coach.heard {
                        Text(heard).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.good)
                    }
                }
                Text(question(step)).font(.system(size: 24, weight: .bold)).foregroundStyle(Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = detail(step) {
                    Text(detail).font(.body).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                }
                if coach.triageAwaitingAnswer {
                    HStack(spacing: 12) {
                        answer(tr("Yes"), yes: true)
                        answer(tr("No"), yes: false)
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface1, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Palette.accent.opacity(0.5), lineWidth: 1.5))
            .animation(.smooth(duration: 0.25), value: step)
        }
    }

    private func answer(_ label: String, yes: Bool) -> some View {
        Button { coach.answerTriage(yes) } label: {
            Text(label).font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(Palette.text)
                .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func question(_ s: CoachModel.TriageStep) -> String {
        switch s {
        case .responsive: tr("Are they responding?")
        case .breathing: tr("Are they breathing normally?")
        case .monitor: tr("Stay with them")
        case .recovery: tr("Put them on their side")
        }
    }

    private func detail(_ s: CoachModel.TriageStep) -> String? {
        switch s {
        case .responsive: tr("Tap their shoulders and shout.")
        case .breathing: tr("Watch the chest for up to 10 seconds. Gasping doesn't count.")
        case .monitor: tr("Call for help if they get worse, and keep checking their breathing.")
        case .recovery: tr("Call for help and keep checking their breathing. Start CPR if it stops.")
        }
    }
}

// MARK: Summary

private struct SummarySheet: View {
    @Environment(CoachModel.self) private var coach
    let summary: SessionSummary

    var body: some View {
        if coach.mode == .emergency { EmergencySummary(summary: summary) } else { trainingSummary }
    }

    private var trainingSummary: some View {
        let s = summary
        return ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if coach.mode == .skillsCheck {
                        SkillsResultCard(summary: s)
                        if let img = skillsShareImage(s) {
                            ShareLink(item: img, preview: SharePreview(tr("Skills check"), image: img)) {
                                Label(tr("Share result"), systemImage: "square.and.arrow.up").font(.subheadline.weight(.semibold))
                            }
                        }
                    }
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(tr("Session score")).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.muted)
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text("\(Int(s.score.rounded()))").font(.system(size: 88, weight: .bold)).tracking(-4)
                                Text("/100").font(.title2.weight(.semibold)).foregroundStyle(Palette.faint)
                            }
                            Text(tr("%@ compressions in %@", "\(s.compressions)", clock(s.elapsed)))
                                .font(.subheadline).foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        Text(s.grade)
                            .font(.system(size: 44, weight: .bold))
                            .foregroundStyle(gradeColor)
                            .frame(width: 76, height: 76)
                            .background(gradeColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .accessibilityLabel(tr("Grade %@", s.grade))
                    }
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible())], alignment: .leading, spacing: 18) {
                        Stat(label: tr("Rate in range"), value: pct(s.ratePct), good: s.ratePct.map { $0 >= 0.8 })
                        Stat(label: s.depthEstimated ? tr("Depth in range (est.)") : tr("Depth in range"), value: pct(s.depthPct), good: s.depthPct.map { $0 >= 0.8 })
                        Stat(label: tr("Hands on chest"), value: pct(s.ccf), good: s.ccf.map { $0 >= 0.8 })
                        Stat(label: tr("Pauses"), value: s.pauses == 0 ? tr("None") : "\(s.pauses)", good: s.pauses == 0)
                        Stat(label: tr("Average rate"), value: s.avgRate.map { "\(Int($0.rounded())) " + tr("/min") } ?? "—", good: nil)
                        Stat(label: tr("Average depth"), value: s.avgDepth.map { (s.depthEstimated ? "≈" : "") + trNumber($0, digits: 1) + " cm" } ?? "—", good: nil)
                        Stat(label: tr("Elbows locked"), value: pct(s.elbowPct), good: s.elbowPct.map { $0 >= 0.8 })
                        Stat(label: tr("Shoulders over hands"), value: pct(s.alignPct), good: s.alignPct.map { $0 >= 0.8 })
                        Stat(label: tr("Full recoil"), value: pct(s.recoilPct), good: s.recoilPct.map { $0 >= 0.8 })
                    }
                    DebriefCard(debrief: coach.debrief)
                    HStack(spacing: 12) {
                        Button { coach.backToSetup() } label: {
                            Text(tr("Done")).frame(maxWidth: .infinity, minHeight: 52)
                                .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        Button { coach.start() } label: {
                            Label(tr("Go again"), systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity, minHeight: 52)
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

private struct DebriefCard: View {
    let debrief: Debrief?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: debrief?.onDevice == true ? "sparkles" : "text.bubble.fill")
                    .foregroundStyle(Palette.accent)
                Text(tr("Debrief")).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.text)
                Spacer()
                if debrief?.onDevice == true {
                    Text(tr("On-device AI")).font(.caption.weight(.medium)).foregroundStyle(Palette.faint)
                }
            }
            if let debrief {
                Text(debrief.text)
                    .font(.body).foregroundStyle(Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(tr("Reviewing your session…")).font(.subheadline).foregroundStyle(Palette.muted)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .animation(.easeOut(duration: 0.25), value: debrief)
        .accessibilityElement(children: .combine)
    }
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

// MARK: Emergency

@MainActor
/// Stands in for the phone call in demo builds: shows what would happen, dials nothing.
private struct SimulatedCallBanner: View {
    @Environment(CoachModel.self) private var coach
    let since: Date

    var body: some View {
        VStack {
            HStack(spacing: 12) {
                Image(systemName: "phone.fill")
                    .font(.headline).foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Palette.good, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(tr("Calling %@", CoachModel.emergencyNumber)).font(.headline).foregroundStyle(Palette.text)
                        Text(since, style: .timer).font(.subheadline.monospacedDigit()).foregroundStyle(Palette.muted)
                    }
                    Text(tr("Demo only. No call is placed.")).font(.caption).foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 8)
                Button { coach.endSimulatedCall() } label: {
                    Image(systemName: "phone.down.fill")
                        .font(.headline).foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Palette.urgent, in: Circle())
                }
                .accessibilityLabel(tr("End demo call"))
            }
            .padding(12)
            .background(Palette.surface1, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Palette.surface2, lineWidth: 1))
            .padding(.horizontal, 12)
            .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
            Spacer()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

extension View {
    /// Shows the demo call banner on top of this view while a simulated call is active.
    func simulatedCallOverlay(_ coach: CoachModel) -> some View {
        overlay {
            // During compressions the call shrinks to a pill in the top bar, clear of the controls.
            if let since = coach.simulatedCallSince, coach.phase != .running { SimulatedCallBanner(since: since) }
        }
        .animation(.spring(duration: 0.35), value: coach.simulatedCallSince)
    }
}

/// Two steps, in order: get help coming, then start compressions. No setup, no countdown.
private struct EmergencySheet: View {
    @Environment(CoachModel.self) private var coach
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Palette.ink.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        Label(tr("Emergency"), systemImage: "staroflife.fill")
                            .font(.system(size: 30, weight: .bold))
                            .labelStyle(TintedIconLabel(tint: Palette.urgent))
                        Spacer()
                        LanguageMenu()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark").font(.headline).foregroundStyle(Palette.muted)
                                .frame(width: 36, height: 36).background(Palette.surface1, in: Circle())
                        }
                        .accessibilityLabel(tr("Close"))
                    }
                    TriageCard()
                    PatientPicker()
                    EmergencyStep(number: 1, title: tr("Call %@", CoachModel.emergencyNumber),
                                  detail: tr("Put the call on speaker. Say someone collapsed and isn't breathing normally. Send anyone nearby for an AED.")) {
                        Button { coach.callEmergency() } label: {
                            Label(tr("Call %@", CoachModel.emergencyNumber), systemImage: "phone.fill")
                                .font(.title3.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 58)
                                .foregroundStyle(.white)
                                .background(Palette.urgent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                    }
                    EmergencyStep(number: 2, title: tr("Start compressions"),
                                  detail: handPlacement(coach.patient)) {
                        Button {
                            coach.startEmergency()
                            dismiss()
                        } label: {
                            Label(tr("Start compressions"), systemImage: "hand.raised.fill")
                                .font(.title3.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 58)
                                .foregroundStyle(Palette.ink)
                                .background(Palette.text, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                    }
                    Text(tr("Keep going until help or an AED arrives, or the person starts breathing normally. Follow the dispatcher's instructions. CPR Coach is a training tool, not a medical device."))
                        .font(.footnote).foregroundStyle(Palette.faint)
                }
                .padding(20)
            }
            .id(coach.language)
        }
        .preferredColorScheme(.dark)
        .onAppear { coach.beginTriage() }
        .onDisappear { coach.endTriage() }
        .onChange(of: coach.phase) { _, p in if p == .running { dismiss() } }
    }
}

private struct EmergencyStep<Action: View>: View {
    let number: Int
    let title: String
    let detail: String
    @ViewBuilder let action: Action
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("\(number)")
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                    .frame(width: 28, height: 28)
                    .background(Palette.text, in: Circle())
                Text(title).font(.system(size: 22, weight: .bold))
            }
            Text(detail).font(.body).foregroundStyle(Palette.muted)
            action
        }
        .padding(18)
        .background(Palette.surface1, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct EmergencySummary: View {
    @Environment(CoachModel.self) private var coach
    @State private var showHandoff = false
    let summary: SessionSummary
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                Text(tr("Compressions stopped")).font(.system(size: 28, weight: .bold))
                Text(tr("%@ compressions over %@. If help hasn't arrived and they aren't breathing normally, keep going.", "\(summary.compressions)", clock(summary.elapsed)))
                    .foregroundStyle(Palette.muted)
                Button { coach.startEmergency() } label: {
                    Label(tr("Resume compressions"), systemImage: "hand.raised.fill").font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 54).foregroundStyle(.white)
                        .background(Palette.urgent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                Button { showHandoff = true } label: {
                    Label(tr("Report for paramedics"), systemImage: "list.clipboard.fill").font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50).foregroundStyle(Palette.ink)
                        .background(Palette.text, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .sheet(isPresented: $showHandoff) { if let r = coach.handoff { HandoffSheet(report: r) } }
                HStack(spacing: 12) {
                    Button { coach.callEmergency() } label: {
                        Label(tr("Call %@", CoachModel.emergencyNumber), systemImage: "phone.fill").frame(maxWidth: .infinity, minHeight: 48)
                            .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    Button { coach.backToSetup() } label: {
                        Text(tr("Done")).frame(maxWidth: .infinity, minHeight: 48)
                            .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .font(.headline).foregroundStyle(Palette.text)
            }
            .padding(24)
            .background(Palette.surface1, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(16)
            .frame(maxWidth: 560)
        }
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
