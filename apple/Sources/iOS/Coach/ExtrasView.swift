// Secondary screens: patient type, AED guide, paramedic handoff report, skills-check result.
import CoreImage.CIFilterBuiltins
import SwiftUI

// MARK: Patient

struct PatientPicker: View {
    @Environment(CoachModel.self) private var coach
    var body: some View {
        @Bindable var coach = coach
        Picker(tr("Patient"), selection: $coach.patient) {
            Text(tr("Adult")).tag(PatientProfile.adult)
            Text(tr("Child")).tag(PatientProfile.child)
            Text(tr("Infant")).tag(PatientProfile.infant)
        }
        .pickerStyle(.segmented)
        .accessibilityLabel(tr("Patient"))
    }
}

/// How to place the hands for this patient (shown in the emergency steps).
func handPlacement(_ p: PatientProfile) -> String {
    switch p {
    case .adult: tr("Kneel beside them. Heel of one hand in the center of the chest, other hand on top, arms straight. Push hard and fast, about 5 cm, twice a second.")
    case .child: tr("Kneel beside them. Heel of one or two hands in the center of the chest, arms straight. Push about 5 cm deep (a third of the chest), twice a second.")
    case .infant: tr("Lay the baby on a firm surface. Two fingers in the center of the chest, just below the nipple line. Push about 4 cm deep (a third of the chest), twice a second.")
    }
}

// MARK: AED

struct AEDGuideSheet: View {
    @Environment(CoachModel.self) private var coach
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let steps: [(String, String, String)] = [
            ("power", tr("Turn it on"), tr("Press the power button or open the lid. Then follow its voice.")),
            ("tshirt", tr("Bare the chest"), tr("Remove or cut clothing. Wipe the chest dry.")),
            ("bandage", tr("Attach the pads"), coach.patient == .adult
                ? tr("One pad below the right collarbone, the other on the left side below the armpit, as pictured on the pads.")
                : tr("Use child pads if there are any. Small chest: one pad on the front, one on the back.")),
            ("hand.raised.slash", tr("Stand clear"), tr("When it analyzes or shocks, nobody touches the person. Say \"Clear!\" out loud.")),
            ("arrow.counterclockwise", tr("Resume compressions"), tr("Straight after a shock, or if no shock is advised. Leave the pads on.")),
        ]
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: s.0)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(Palette.good)
                                .frame(width: 48, height: 48)
                                .background(Palette.good.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(i + 1). \(s.1)").font(.headline).foregroundStyle(Palette.text)
                                Text(s.2).font(.subheadline).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.surface1, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    Text(tr("Keep compressions going while the pads go on. Only pause when the AED tells you to."))
                        .font(.footnote).foregroundStyle(Palette.faint)
                }
                .padding(16)
            }
            .background(Palette.ink)
            .navigationTitle(tr("Using the AED"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(tr("Done")) { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: Handoff

struct HandoffSheet: View {
    let report: HandoffReport
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let s = report.summary
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let mins = report.minutesSinceFound() {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tr("Found")).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.muted)
                            Text(tr("%@ min ago", "\(mins)")).font(.system(size: 44, weight: .bold)).foregroundStyle(Palette.text)
                        }
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(report.events.enumerated()), id: \.offset) { _, e in
                            HStack(spacing: 12) {
                                Text(HandoffReport.clock(e.at)).font(.subheadline.monospacedDigit()).foregroundStyle(Palette.muted)
                                Text(e.label).font(.subheadline.weight(.medium)).foregroundStyle(Palette.text)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 8)
                            Divider().overlay(Palette.surface2)
                        }
                    }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 14) {
                        fact(tr("CPR time"), String(format: "%d:%02d", Int(s.elapsed) / 60, Int(s.elapsed) % 60))
                        fact(tr("Compressions"), "\(s.compressions)")
                        fact(tr("Average rate"), s.avgRate.map { "\(Int($0.rounded())) " + tr("/min") } ?? "—")
                        fact(tr("Average depth"), s.avgDepth.map { trNumber($0, digits: 1) + " cm" } ?? "—")
                        fact(tr("Hands on chest"), s.ccf.map { "\(Int(($0 * 100).rounded()))%" } ?? "—")
                        fact(tr("Rescuer switches"), "\(report.swaps)")
                    }
                    HStack(alignment: .center, spacing: 16) {
                        if let qr = qrImage(report.text()) {
                            Image(uiImage: qr).interpolation(.none).resizable()
                                .frame(width: 132, height: 132)
                                .padding(8).background(.white, in: RoundedRectangle(cornerRadius: 12))
                                .accessibilityLabel(tr("QR code of this report"))
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            Text(tr("Paramedics can scan this, or you can send it.")).font(.subheadline).foregroundStyle(Palette.muted)
                            ShareLink(item: report.text()) {
                                Label(tr("Share report"), systemImage: "square.and.arrow.up")
                                    .font(.headline).foregroundStyle(.white)
                                    .padding(.horizontal, 16).frame(height: 44)
                                    .background(Palette.accent, in: Capsule())
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Palette.ink)
            .navigationTitle(tr("For paramedics"))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(tr("Done")) { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundStyle(Palette.faint)
            Text(value).font(.system(.title3, weight: .semibold)).foregroundStyle(Palette.text)
        }
    }
}

func qrImage(_ text: String) -> UIImage? {
    let f = CIFilter.qrCodeGenerator()
    f.message = Data(text.utf8)
    f.correctionLevel = "M"
    guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
          let cg = CIContext().createCGImage(out, from: out.extent) else { return nil }
    return UIImage(cgImage: cg)
}

// MARK: Skills check result

struct SkillsResultCard: View {
    let summary: SessionSummary

    var body: some View {
        let passed = SkillsCheck.passed(summary)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: passed ? "checkmark.seal.fill" : "xmark.seal.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(passed ? Palette.good : Palette.urgent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("Skills check")).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.muted)
                    Text(passed ? tr("Passed") : tr("Not yet")).font(.system(size: 34, weight: .bold)).foregroundStyle(Palette.text)
                }
            }
            ForEach(Array(SkillsCheck.criteria(summary).enumerated()), id: \.offset) { _, c in
                HStack(spacing: 10) {
                    Image(systemName: c.passed == nil ? "minus.circle" : c.passed! ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(c.passed == nil ? Palette.faint : c.passed! ? Palette.good : Palette.urgent)
                    Text(c.name).foregroundStyle(Palette.text)
                    Spacer()
                    Text(c.value.map { "\(Int(($0 * 100).rounded()))%" } ?? tr("Not measured"))
                        .font(.body.monospacedDigit()).foregroundStyle(Palette.muted)
                }
                .font(.subheadline)
            }
            Text(tr("Pass: every measured skill at 80% or better over 2 minutes."))
                .font(.caption).foregroundStyle(Palette.faint)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// The result card as an image, for sharing.
@MainActor
func skillsShareImage(_ s: SessionSummary) -> Image? {
    let r = ImageRenderer(content: SkillsResultCard(summary: s).frame(width: 360).padding(16).background(Palette.ink))
    r.scale = 3
    return r.uiImage.map { Image(uiImage: $0) }
}
