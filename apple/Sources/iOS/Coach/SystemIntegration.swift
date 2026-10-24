// Outside the app: "Hey Siri, start CPR" (also assignable to the Action button) and the Live
// Activity that keeps the instruction, rate and depth on the lock screen during a session.
import ActivityKit
import AppIntents
import Foundation

// MARK: Siri / Shortcuts / Action button

struct StartEmergencyIntent: AppIntent {
    static let title: LocalizedStringResource = "Start CPR emergency"
    static let description = IntentDescription("Opens CPR Coach's emergency check and coaching straight away.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        CoachModel.requestEmergency()
        return .result()
    }
}

struct StartPracticeIntent: AppIntent {
    static let title: LocalizedStringResource = "Start CPR practice"
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        CoachModel.requestPractice()
        return .result()
    }
}

struct CPRShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartEmergencyIntent(), phrases: [
            "Start CPR with \(.applicationName)",
            "\(.applicationName) emergency",
            "Someone collapsed, open \(.applicationName)",
        ], shortTitle: "CPR emergency", systemImageName: "staroflife.fill")
        AppShortcut(intent: StartPracticeIntent(), phrases: [
            "Practice CPR with \(.applicationName)",
        ], shortTitle: "Practice CPR", systemImageName: "heart.fill")
    }
}

// MARK: Live Activity

@MainActor
final class LiveActivityController {
    private var activity: Activity<CPRActivityAttributes>?
    private var last: CPRActivityAttributes.ContentState?
    private var lastPush = Date.distantPast

    func start(emergency: Bool) {
        end()
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attrs = CPRActivityAttributes(startedAt: Date(), emergency: emergency,
                                          title: emergency ? tr("Emergency") : "CPR Coach")
        let state = CPRActivityAttributes.ContentState(rate: nil, depth: nil, instruction: tr("Start compressions"),
                                                       tone: "warning", rateUnit: tr("/min"))
        activity = try? Activity.request(attributes: attrs, content: .init(state: state, staleDate: nil))
        last = state
    }

    /// At most once a second, and only when something visible changed.
    func update(rate: Double?, depth: Double?, instruction: String, tone: CoachTone) {
        guard let activity else { return }
        let toneName = switch tone {
        case .good: "good"
        case .urgent: "urgent"
        case .swap: "swap"
        case .warning: "warning"
        }
        let state = CPRActivityAttributes.ContentState(rate: rate.map { Int($0.rounded()) }, depth: depth.map { ($0 * 10).rounded() / 10 },
                                                       instruction: instruction, tone: toneName, rateUnit: tr("/min"))
        guard state != last, Date().timeIntervalSince(lastPush) >= 1 else { return }
        last = state
        lastPush = Date()
        nonisolated(unsafe) let a = activity // ActivityKit handles its own synchronisation
        Task { await a.update(.init(state: state, staleDate: nil)) }
    }

    func end() {
        guard let activity else { return }
        self.activity = nil
        nonisolated(unsafe) let a = activity
        Task { await a.end(nil, dismissalPolicy: .after(.now + 60)) }
    }
}
