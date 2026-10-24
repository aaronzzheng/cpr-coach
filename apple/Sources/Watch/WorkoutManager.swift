// HealthKit workout session: keeps the app running with full-rate sensors while the wrist
// moves and the screen dims, and streams heart rate to the phone.
import Foundation
import HealthKit

nonisolated final class WorkoutManager: NSObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate,
    @unchecked Sendable
{
    private let store = HKHealthStore()
    private let link: PhoneLink
    private let events: AsyncStream<WatchEvent>.Continuation
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    init(link: PhoneLink, events: AsyncStream<WatchEvent>.Continuation) {
        self.link = link
        self.events = events
        super.init()
    }

    func requestAuthorization() async throws {
        try await store.requestAuthorization(
            toShare: [HKObjectType.workoutType()],
            read: [HKQuantityType(.heartRate)]
        )
    }

    func start() async throws {
        let config = HKWorkoutConfiguration()
        config.activityType = .other
        config.locationType = .indoor

        let session = try HKWorkoutSession(healthStore: store, configuration: config)
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
        session.delegate = self
        builder.delegate = self
        self.session = session
        self.builder = builder

        let now = Date()
        session.startActivity(with: now)
        try await builder.beginCollection(at: now)
    }

    /// Ends the session; collection is closed and the workout saved once it reports `.ended`.
    func stop() {
        session?.end()
    }

    // MARK: HKWorkoutSessionDelegate

    func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        guard toState == .ended else { return }
        // Finish the builder that belongs to *this* session. A new workout may already have
        // started (Stop then Start quickly), and its session/builder must not be touched.
        let endedBuilder = workoutSession.associatedWorkoutBuilder()
        Task { [self] in
            try? await endedBuilder.endCollection(at: date)
            _ = try? await endedBuilder.finishWorkout()
            if session === workoutSession {
                session = nil
                builder = nil
            }
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: any Error) {
        events.yield(.workoutError(error.localizedDescription))
    }

    // MARK: HKLiveWorkoutBuilderDelegate

    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let hr = HKQuantityType(.heartRate)
        guard collectedTypes.contains(hr),
              let quantity = workoutBuilder.statistics(for: hr)?.mostRecentQuantity()
        else { return }
        let bpm = Int(quantity.doubleValue(for: .count().unitDivided(by: .minute())).rounded())
        link.sendHeartRate(bpm: bpm, ts: ProcessInfo.processInfo.systemUptime)
        events.yield(.heartRate(bpm))
    }

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
