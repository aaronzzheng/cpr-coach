// Voice coach (AVSpeechSynthesizer) and a sample-accurate looping metronome (AVAudioEngine).
// The audio session plays through the silent switch, since the rescuer can't fiddle with the phone.
import AVFoundation

@MainActor
final class CoachAudio {
    private let synth = AVSpeechSynthesizer()
    private var currentPriority: Int?
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var engineReady = false
    var muted = false {
        didSet { if muted { synth.stopSpeaking(at: .immediate) } }
    }

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    /// Lower priority number = more important; only a more important line interrupts.
    func say(_ text: String, priority: Int) {
        guard !muted else { return }
        if synth.isSpeaking {
            if let cur = currentPriority, priority >= cur { return }
            synth.stopSpeaking(at: .immediate)
        }
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "en-US")
        u.rate = 0.55
        currentPriority = priority
        synth.speak(u)
    }

    func startMetronome(bpm: Int) {
        stopMetronome()
        if !engineReady {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: nil)
            engineReady = true
        }
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        let rate = format.sampleRate > 0 ? format.sampleRate : 48_000
        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
              let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(rate * 60 / Double(bpm))) else { return }
        // One beat: a 30 ms decaying 1 kHz click, then silence until the next beat. Looping it
        // gives a drift-free tempo straight from the audio clock.
        buf.frameLength = buf.frameCapacity
        let samples = buf.floatChannelData![0]
        let clickFrames = Int(rate * 0.03)
        for i in 0..<Int(buf.frameLength) {
            samples[i] = i < clickFrames ? Float(sin(2 * .pi * 1000 * Double(i) / rate) * exp(-Double(i) / (rate * 0.006))) * 0.8 : 0
        }
        engine.disconnectNodeOutput(player)
        engine.connect(player, to: engine.mainMixerNode, format: fmt)
        try? engine.start()
        player.scheduleBuffer(buf, at: nil, options: .loops)
        player.play()
    }

    func stopMetronome() {
        player.stop()
    }
}
