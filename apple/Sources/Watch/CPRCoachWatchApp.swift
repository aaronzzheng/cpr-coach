// Watch app entry point and the UI model that ties workout, motion, metronome and phone link.
import Observation
import SwiftUI

@main
struct CPRCoachWatchApp: App {
    @State private var model = WatchModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
        }
    }
}

@MainActor
@Observable
final class WatchModel {
    var running = false
    var phoneReachable = false
    var samplesSent = 0
    var batchesDropped = 0
    var heartRate: Int?
    var error: String?
    var bpm = 110
    var metronomeOn = true {
        didSet { syncMetronome() }
    }
    var everyOtherBeat = false {
        didSet { metronome.everyOtherBeat = everyOtherBeat }
    }

    @ObservationIgnored private let phone: PhoneLink
    @ObservationIgnored private let motion: MotionStreamer
    @ObservationIgnored private let workout: WorkoutManager
    @ObservationIgnored private let metronome = Metronome()

    init() {
        let (stream, events) = AsyncStream.makeStream(of: WatchEvent.self)
        phone = PhoneLink(events: events)
        motion = MotionStreamer(link: phone)
        workout = WorkoutManager(link: phone, events: events)
        Task { [weak self] in
            for await event in stream {
                self?.apply(event)
            }
        }
        phone.activate()
    }

    func start() async {
        guard !running else { return }
        error = nil
        running = true
        do {
            try await workout.requestAuthorization()
            try await workout.start()
        } catch {
            // Keep streaming without the workout; it just may throttle when the screen dims.
            self.error = "Workout: \(error.localizedDescription)"
        }
        guard running else { return }
        if !motion.isAvailable { error = "Device motion unavailable" }
        motion.start()
        syncMetronome()
    }

    func stop() {
        guard running else { return }
        running = false
        motion.stop()
        workout.stop()
        syncMetronome()
    }

    private func syncMetronome() {
        if running && metronomeOn {
            if !metronome.isRunning || metronome.bpm != bpm { metronome.start(bpm: bpm) }
        } else {
            metronome.stop()
        }
    }

    private func apply(_ event: WatchEvent) {
        switch event {
        case .reachability(let r): phoneReachable = r
        case .sent(let n): samplesSent += n
        case .dropped: batchesDropped += 1
        case .heartRate(let bpm): heartRate = bpm
        case .workoutError(let msg): error = "Workout: \(msg)"
        case .command(let cmd): handle(cmd)
        }
    }

    private func handle(_ cmd: WatchCommand) {
        switch cmd {
        case .start: Task { await start() }
        case .stop: stop()
        case .metronome(let on, let newBpm):
            bpm = newBpm
            metronomeOn = on
            syncMetronome()
        }
    }
}
