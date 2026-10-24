// Haptic metronome on the wrist. The laptop's audio metronome is primary; the Taptic Engine
// may merge taps at 110 BPM, so "every other beat" halves the rate (55 taps/min).
import Foundation
import WatchKit

@MainActor
final class Metronome {
    var everyOtherBeat = false {
        didSet { if isRunning { start(bpm: bpm) } }
    }
    var haptic: WKHapticType = .click
    private(set) var bpm = 110
    private var timer: DispatchSourceTimer?

    var isRunning: Bool { timer != nil }

    func start(bpm: Int) {
        stop()
        self.bpm = bpm
        let interval = 60.0 / Double(bpm) * (everyOtherBeat ? 2 : 1)
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(5))
        t.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.tick() }
        }
        t.resume()
        timer = t
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func tick() {
        WKInterfaceDevice.current().play(haptic)
    }
}
