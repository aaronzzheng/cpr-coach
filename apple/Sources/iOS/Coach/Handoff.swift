// Emergency timeline and the paramedic handoff: when the collapse was found, when help was
// called, how long CPR has run, its quality, and when the AED arrived — the first questions EMS
// ask. Also the skills-check pass criteria. Pure Foundation so it's testable on the Mac.
import Foundation

nonisolated struct TimelineEvent: Sendable, Equatable {
    enum Kind: Sendable { case check, call, compressions, swap, aed, stopped }
    let at: Date
    let kind: Kind

    var label: String {
        switch kind {
        case .check: tr("Collapse found, checked response")
        case .call: tr("Emergency services called")
        case .compressions: tr("Compressions started")
        case .swap: tr("Rescuers switched")
        case .aed: tr("AED arrived")
        case .stopped: tr("Compressions stopped")
        }
    }
}

nonisolated struct HandoffReport: Sendable {
    let events: [TimelineEvent]
    let summary: SessionSummary
    let swaps: Int
    let patient: PatientProfile

    var foundAt: Date? { events.first { $0.kind == .check || $0.kind == .compressions }?.at }

    static func clock(_ d: Date) -> String { d.formatted(date: .omitted, time: .standard) }

    /// Minutes since the collapse was found (EMS call this the "down time" they can account for).
    func minutesSinceFound(now: Date = Date()) -> Int? { foundAt.map { Int(now.timeIntervalSince($0) / 60) } }

    /// Plain text for sharing or the QR code.
    func text(now: Date = Date()) -> String {
        var lines = [tr("CPR Coach handoff"), ""]
        for e in events { lines.append("\(Self.clock(e.at))  \(e.label)") }
        lines.append("")
        let s = summary
        let mins = Int(s.elapsed) / 60, secs = Int(s.elapsed) % 60
        lines.append(tr("CPR time: %@ min %@ s", "\(mins)", "\(secs)"))
        lines.append(tr("Compressions: %@", "\(s.compressions)"))
        if let r = s.avgRate { lines.append(tr("Average rate: %@ /min", "\(Int(r.rounded()))")) }
        if let d = s.avgDepth { lines.append(tr("Average depth: %@ cm", String(format: "%.1f", d))) }
        if let c = s.ccf { lines.append(tr("Hands-on time: %@", "\(Int((c * 100).rounded()))%")) }
        lines.append(tr("Pauses over 2 s: %@ (longest %@ s)", "\(s.pauses)", "\(Int(s.longestPause.rounded()))"))
        lines.append(tr("Rescuer switches: %@", "\(swaps)"))
        if patient != .adult { lines.append(tr("Patient: %@", patient == .child ? tr("Child") : tr("Infant"))) }
        return lines.joined(separator: "\n")
    }
}

// MARK: Skills check

/// A 2-minute test with pass/fail per skill, modelled on an instructor-led skills check.
nonisolated enum SkillsCheck {
    static let durationS = 120.0
    static let passFraction = 0.8

    struct Criterion: Sendable {
        let name: String
        let value: Double?      // fraction 0–1; nil = not measured
        var passed: Bool? { value.map { $0 >= passFraction } }
    }

    static func criteria(_ s: SessionSummary) -> [Criterion] {
        [
            Criterion(name: tr("Rate 100–120"), value: s.ratePct),
            Criterion(name: tr("Depth on target"), value: s.depthEstimated ? nil : s.depthPct),
            Criterion(name: tr("Full recoil"), value: s.recoilPct),
            Criterion(name: tr("Hands on chest"), value: s.ccf),
            Criterion(name: tr("Elbows locked"), value: s.elbowPct),
        ]
    }

    /// Passes when every measured skill is at 80% or better, rate always being required.
    static func passed(_ s: SessionSummary) -> Bool {
        guard s.ratePct != nil, s.elapsed >= durationS - 5 else { return false }
        return criteria(s).allSatisfy { $0.passed != false }
    }
}
