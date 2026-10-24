// First launch: what the coach does and the permissions it needs, asked for together with the
// reason for each, instead of three surprise prompts mid-session.
import AVFoundation
import Speech
import SwiftUI

struct OnboardingView: View {
    @Environment(CoachModel.self) private var coach
    let done: () -> Void

    var body: some View {
        @Bindable var coach = coach
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Spacer()
                    LanguageMenuLite(language: $coach.language)
                }
                Image(systemName: "heart.fill")
                    .font(.system(size: 44)).foregroundStyle(Palette.accent)
                Text("CPR Coach").font(.system(size: 40, weight: .bold)).tracking(-1)
                Text(tr("Real-time coaching for chest compressions, from your phone's camera and your Apple Watch."))
                    .font(.title3).foregroundStyle(Palette.muted)
                VStack(alignment: .leading, spacing: 16) {
                    row("camera.fill", tr("Camera"), tr("Watches your arms from the side: elbows, shoulders, recoil and hand position. Video never leaves the phone."))
                    row("applewatch", tr("Apple Watch"), tr("Measures rate and depth from your wrist, and taps the beat."))
                    row("mic.fill", tr("Hands-free voice"), tr("Say \"swap\", \"how long\" or \"how am I doing\" while your hands are busy."))
                    row("staroflife.fill", tr("Emergency mode"), tr("Walks you through checking the person, calling for help and CPR."))
                }
                Button {
                    Task {
                        _ = await AVCaptureDevice.requestAccess(for: .video)
                        _ = await AVAudioApplication.requestRecordPermission()
                        _ = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
                            SFSpeechRecognizer.requestAuthorization { @Sendable s in c.resume(returning: s == .authorized) }
                        }
                        done()
                    }
                } label: {
                    Text(tr("Continue"))
                        .font(.headline).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(Palette.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                Text(tr("Training tool, not a medical device. In an emergency, call your local emergency number first."))
                    .font(.caption).foregroundStyle(Palette.faint)
            }
            .padding(24)
            .id(coach.language)
        }
        .background(Palette.ink.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private func row(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3).foregroundStyle(Palette.accent)
                .frame(width: 44, height: 44)
                .background(Palette.surface1, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(Palette.text)
                Text(detail).font(.subheadline).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Language menu bound directly (the onboarding sits outside the coach screen's environment refresh).
private struct LanguageMenuLite: View {
    @Binding var language: AppLanguage
    var body: some View {
        Menu {
            Picker(tr("Language"), selection: $language) {
                ForEach(AppLanguage.allCases) { Text($0.nativeName).tag($0) }
            }
        } label: {
            Label(language.nativeName, systemImage: "globe")
                .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.text)
                .padding(.horizontal, 12).frame(height: 34)
                .background(Palette.surface2, in: Capsule())
        }
    }
}
