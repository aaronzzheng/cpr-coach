// Post-session debrief: what went well, the one thing to fix next, and why it matters.
//
// The facts and priorities always come from rules over the session stats, so the advice is
// grounded in what was measured. On devices with Apple Intelligence, Apple's on-device language
// model turns those facts into a short spoken-style debrief in the app's language; nothing leaves
// the phone. Elsewhere the rule text is shown as is, translated.
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

nonisolated struct Debrief: Sendable, Equatable {
    var text: String
    var onDevice: Bool
}

/// An English template with `%@` slots, renderable in English (for the model) or translated.
nonisolated struct Phrase: Sendable {
    var format: String
    var args: [String] = []
    var english: String { args.reduce(format) { s, a in s.range(of: "%@").map { s.replacingCharacters(in: $0, with: a) } ?? s } }
    var localized: String {
        var s = tr(format)
        for a in args { if let r = s.range(of: "%@") { s.replaceSubrange(r, with: a) } }
        return s
    }
}

/// One finding from the session stats, most important first.
nonisolated struct DebriefFinding: Sendable {
    var fact: Phrase
    var fix: Phrase?
}

nonisolated func debriefFindings(_ s: SessionSummary) -> [DebriefFinding] {
    var out: [(priority: Int, f: DebriefFinding)] = []
    func pct(_ x: Double) -> String { "\(Int((x * 100).rounded()))%" }
    func cm(_ x: Double) -> String { String(format: "%.1f", x) }

    if let c = s.ccf, c < 0.8 {
        out.append((0, DebriefFinding(
            fact: Phrase(format: "Hands were on the chest %@ of the time, with %@ pauses (longest %@ s).",
                         args: [pct(c), "\(s.pauses)", "\(Int(s.longestPause.rounded()))"]),
            fix: Phrase(format: "Keep pauses under 10 seconds; blood flow to the brain drops every time compressions stop."))))
    }
    if let d = s.avgDepth, !s.depthEstimated, d < Targets.depthOkMin {
        out.append((1, DebriefFinding(
            fact: Phrase(format: "Average depth was %@ cm, under the %@ cm target.", args: [cm(d), cm(Targets.depthMin)]),
            fix: Phrase(format: "Lock your elbows and push with your body weight from the shoulders, not your arms."))))
    } else if let d = s.avgDepth, !s.depthEstimated, d > Targets.depthOkMax {
        out.append((2, DebriefFinding(
            fact: Phrase(format: "Average depth was %@ cm, deeper than the %@ cm limit.", args: [cm(d), cm(Targets.depthMax)]),
            fix: Phrase(format: "Ease off slightly; going deeper raises the risk of injury without helping blood flow."))))
    }
    if let r = s.avgRate, r < Targets.rateMin {
        out.append((1, DebriefFinding(
            fact: Phrase(format: "Average rate was %@ per minute, below the 100 to 120 target.", args: ["\(Int(r.rounded()))"]),
            fix: Phrase(format: "Follow the metronome; slower compressions move less blood."))))
    } else if let r = s.avgRate, r > Targets.rateMax {
        out.append((2, DebriefFinding(
            fact: Phrase(format: "Average rate was %@ per minute, above the 100 to 120 target.", args: ["\(Int(r.rounded()))"]),
            fix: Phrase(format: "Slow down to the beat so the chest has time to fill between pushes."))))
    }
    if let r = s.recoilPct, r < 0.8 {
        out.append((2, DebriefFinding(
            fact: Phrase(format: "The chest came all the way back up on %@ of compressions.", args: [pct(r)]),
            fix: Phrase(format: "Lift your weight off between pushes; the heart refills only when the chest fully rises."))))
    }
    if let e = s.elbowPct, e < 0.8 {
        out.append((3, DebriefFinding(
            fact: Phrase(format: "Elbows were locked %@ of the time.", args: [pct(e)]),
            fix: Phrase(format: "Straight arms let your body weight do the work, so you tire less."))))
    }
    if let a = s.alignPct, a < 0.8 {
        out.append((3, DebriefFinding(
            fact: Phrase(format: "Shoulders were over your hands %@ of the time.", args: [pct(a)]),
            fix: Phrase(format: "Move your shoulders directly above the hands so you push straight down."))))
    }
    // Strengths, so the debrief isn't only criticism.
    if let r = s.ratePct, r >= 0.8 { out.append((9, DebriefFinding(fact: Phrase(format: "Rate was on target %@ of the time.", args: [pct(r)])))) }
    if let d = s.depthPct, d >= 0.8, !s.depthEstimated { out.append((9, DebriefFinding(fact: Phrase(format: "Depth was on target %@ of the time.", args: [pct(d)])))) }
    if let c = s.ccf, c >= 0.8 { out.append((9, DebriefFinding(fact: Phrase(format: "You kept your hands on the chest %@ of the time.", args: [pct(c)])))) }
    return out.sorted { $0.priority < $1.priority }.map(\.f)
}

/// Plain rule-based debrief in the app's language: the top fix plus one strength.
nonisolated func ruleDebrief(_ s: SessionSummary) -> String {
    guard s.compressions >= 10 else { return tr("That session was too short to grade. Aim for at least two minutes of compressions.") }
    let f = debriefFindings(s)
    let fixes = f.filter { $0.fix != nil }
    let strength = f.first { $0.fix == nil }
    guard let top = fixes.first, let fix = top.fix else {
        return tr("Excellent work: rate, depth and posture all stayed on target. Keep it up for the full two minutes before swapping.")
    }
    var parts = [top.fact.localized, fix.localized]
    if let strength {
        let fact = strength.fact.localized
        parts.append(tr("Also good: %@", fact.prefix(1).lowercased() + fact.dropFirst()))
    }
    return parts.joined(separator: " ")
}

/// The debrief for a session: on-device model when available, rules otherwise.
func makeDebrief(_ s: SessionSummary, language: AppLanguage) async -> Debrief {
    let fallback = Debrief(text: ruleDebrief(s), onDevice: false)
    guard s.compressions >= 10 else { return fallback }
    #if canImport(FoundationModels)
    if #available(iOS 26.0, *), case .available = SystemLanguageModel.default.availability,
       SystemLanguageModel.default.supportsLocale(language.locale) {
        let facts = debriefFindings(s).map { f in "- " + f.fact.english + (f.fix.map { " Fix: " + $0.english } ?? "") }.joined(separator: "\n")
        let session = LanguageModelSession(instructions: """
            You are a calm, encouraging CPR instructor giving a trainee feedback after a practice \
            session. Use only the facts provided; never invent numbers. Write three short sentences \
            in second person: first the single most important thing to fix and how, then why it \
            matters, then one thing they did well. No lists, no headings, under 70 words. \
            Respond in \(language.englishName).
            """)
        do {
            let prompt = """
                Session: \(s.compressions) compressions in \(Int(s.elapsed.rounded())) seconds, score \(Int(s.score.rounded())) of 100.
                Findings, most important first:
                \(facts)
                """
            let reply = try await session.respond(to: prompt).content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !reply.isEmpty { return Debrief(text: reply, onDevice: true) }
        } catch {
            return fallback
        }
    }
    #endif
    return fallback
}
