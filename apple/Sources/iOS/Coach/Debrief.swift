// Post-session debrief: what went well, the one thing to fix next, and why it matters.
//
// The facts and priorities always come from rules over the session stats, so the advice is
// grounded in what was measured. On devices with Apple Intelligence, Apple's on-device language
// model turns those facts into a short spoken-style debrief; nothing leaves the phone. Elsewhere
// the rule text is shown as is.
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

nonisolated struct Debrief: Sendable, Equatable {
    var text: String
    var onDevice: Bool
}

/// One finding from the session stats, most important first.
nonisolated struct DebriefFinding: Sendable {
    var fact: String
    var fix: String?
}

nonisolated func debriefFindings(_ s: SessionSummary) -> [DebriefFinding] {
    var out: [(priority: Int, f: DebriefFinding)] = []
    func pct(_ x: Double) -> String { "\(Int((x * 100).rounded()))%" }

    if let c = s.ccf, c < 0.8 {
        out.append((0, DebriefFinding(
            fact: "Hands were on the chest \(pct(c)) of the time, with \(s.pauses) pause\(s.pauses == 1 ? "" : "s") (longest \(Int(s.longestPause.rounded())) s).",
            fix: "Keep pauses under 10 seconds; blood flow to the brain drops every time compressions stop.")))
    }
    if let d = s.avgDepth, !s.depthEstimated, d < Targets.depthMin {
        out.append((1, DebriefFinding(
            fact: String(format: "Average depth was %.1f cm, under the 5 cm target.", d),
            fix: "Lock your elbows and push with your body weight from the shoulders, not your arms.")))
    } else if let d = s.avgDepth, !s.depthEstimated, d > Targets.depthMax {
        out.append((2, DebriefFinding(
            fact: String(format: "Average depth was %.1f cm, deeper than the 6 cm limit.", d),
            fix: "Ease off slightly; going past 6 cm raises the risk of injury without helping blood flow.")))
    }
    if let r = s.avgRate, r < Targets.rateMin {
        out.append((1, DebriefFinding(
            fact: "Average rate was \(Int(r.rounded())) per minute, below the 100 to 120 target.",
            fix: "Follow the metronome; slower compressions move less blood.")))
    } else if let r = s.avgRate, r > Targets.rateMax {
        out.append((2, DebriefFinding(
            fact: "Average rate was \(Int(r.rounded())) per minute, above the 100 to 120 target.",
            fix: "Slow down to the beat so the chest has time to fill between pushes.")))
    }
    if let e = s.elbowPct, e < 0.8 {
        out.append((3, DebriefFinding(
            fact: "Elbows were locked \(pct(e)) of the time.",
            fix: "Straight arms let your body weight do the work, so you tire less.")))
    }
    if let a = s.alignPct, a < 0.8 {
        out.append((3, DebriefFinding(
            fact: "Shoulders were over your hands \(pct(a)) of the time.",
            fix: "Move your shoulders directly above the hands so you push straight down.")))
    }
    // Strengths, so the debrief isn't only criticism.
    if let r = s.ratePct, r >= 0.8 { out.append((9, DebriefFinding(fact: "Rate was on target \(pct(r)) of the time.", fix: nil))) }
    if let d = s.depthPct, d >= 0.8, !s.depthEstimated { out.append((9, DebriefFinding(fact: "Depth was on target \(pct(d)) of the time.", fix: nil))) }
    if let c = s.ccf, c >= 0.8 { out.append((9, DebriefFinding(fact: "You kept your hands on the chest \(pct(c)) of the time.", fix: nil))) }
    return out.sorted { $0.priority < $1.priority }.map(\.f)
}

/// Plain rule-based debrief: the top fix plus one strength.
nonisolated func ruleDebrief(_ s: SessionSummary) -> String {
    let f = debriefFindings(s)
    guard s.compressions >= 10 else { return "That session was too short to grade. Aim for at least two minutes of compressions." }
    let fixes = f.filter { $0.fix != nil }
    let strength = f.first { $0.fix == nil }
    guard let top = fixes.first else {
        return "Excellent work: rate, depth and posture all stayed on target. Keep it up for the full two minutes before swapping."
    }
    var parts = [top.fact, top.fix!]
    if let strength { parts.append("Good news: " + strength.fact.prefix(1).lowercased() + strength.fact.dropFirst()) }
    return parts.joined(separator: " ")
}

/// The debrief for a session: on-device model when available, rules otherwise.
func makeDebrief(_ s: SessionSummary) async -> Debrief {
    let fallback = Debrief(text: ruleDebrief(s), onDevice: false)
    guard s.compressions >= 10 else { return fallback }
    #if canImport(FoundationModels)
    if #available(iOS 26.0, *), case .available = SystemLanguageModel.default.availability {
        let facts = debriefFindings(s).map { f in "- " + f.fact + (f.fix.map { " Fix: " + $0 } ?? "") }.joined(separator: "\n")
        let session = LanguageModelSession(instructions: """
            You are a calm, encouraging CPR instructor giving a trainee feedback after a practice \
            session. Use only the facts provided; never invent numbers. Write three short sentences \
            in second person: first the single most important thing to fix and how, then why it \
            matters, then one thing they did well. No lists, no headings, under 70 words.
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
