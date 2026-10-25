// Voice coach (AVSpeechSynthesizer) and a sample-accurate looping metronome (AVAudioEngine).
// The audio session plays through the silent switch, since the rescuer can't fiddle with the phone.
import AVFoundation

@MainActor
final class CoachAudio: NSObject, AVSpeechSynthesizerDelegate {
    private let synth = AVSpeechSynthesizer()
    private var lastSpeechEnd = Date.distantPast
    private var currentPriority: Int?
    private var currentLine: String?
    /// Called when the coach finishes talking, so voice commands can start listening afresh.
    var onSpeechEnd: (() -> Void)?
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var engineReady = false
    private var metronomeBPM: Int?
    var muted = false {
        didSet { if muted { synth.stopSpeaking(at: .immediate) } }
    }

    /// What the coach is saying (or said a moment ago), so voice commands can ignore its words
    /// without ignoring the rescuer talking over it.
    var echoLine: String? {
        synth.isSpeaking || Date().timeIntervalSince(lastSpeechEnd) < 0.3 ? currentLine : nil
    }

    override init() {
        super.init()
        synth.delegate = self
        // Play-and-record so voice commands can listen while the coach talks and the metronome ticks;
        // still loud on the speaker and through the silent switch.
        try? AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        // A phone call (e.g. to emergency services) interrupts our audio; restart the metronome after.
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let ended = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init) == .ended
            guard ended else { return }
            MainActor.assumeIsolated {
                try? AVAudioSession.sharedInstance().setActive(true)
                if let self, let bpm = self.metronomeBPM { self.startMetronome(bpm: bpm) }
            }
        }
        // Turning the microphone on for voice commands can reconfigure audio and stop this engine.
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                if let self, let bpm = self.metronomeBPM { self.startMetronome(bpm: bpm) }
            }
        }
    }

    /// Lower priority number = more important; only a more important line interrupts, unless
    /// `interrupt` (a reply the rescuer just asked for).
    func say(_ text: String, priority: Int, interrupt: Bool = false) {
        guard !muted else { return }
        if synth.isSpeaking {
            if !interrupt, let cur = currentPriority, priority >= cur { return }
            synth.stopSpeaking(at: .immediate)
        }
        let u = AVSpeechUtterance(string: text)
        let lang = AppLanguage.current
        u.voice = AVSpeechSynthesisVoice(language: lang.locale.identifier(.bcp47))
        u.rate = lang == .en ? 0.55 : 0.5
        currentPriority = priority
        currentLine = text
        synth.speak(u)
    }

    func startMetronome(bpm: Int) {
        stopMetronome()
        metronomeBPM = bpm
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

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        Task { @MainActor in self.speechEnded() }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) {
        Task { @MainActor in self.speechEnded() }
    }

    private func speechEnded() {
        lastSpeechEnd = Date()
        if !synth.isSpeaking { onSpeechEnd?() } // not when cut off by the next line
    }

    func stopMetronome() {
        player.stop()
        metronomeBPM = nil
    }
}
