// Hands-free voice commands. During CPR both hands are on the chest, so the rescuer talks to the
// coach instead: "swap", "how long", "how am I doing", "call for help", "stop", and yes/no answers
// in the emergency check. Speech is recognised on the phone (on-device model where the language
// has one), and the coach's own voice is ignored so it never answers itself.
import AVFoundation
import Speech

nonisolated enum VoiceCommand: Equatable, Sendable {
    case stop, swap, time, status, call, yes, no
}

/// Keyword spotting per language. Negatives win over positives ("not breathing" is a no), and
/// "don't stop" never stops.
nonisolated enum CommandMatcher {
    private struct Words {
        var stop: [String], dontStop: [String], swap: [String], time: [String], status: [String], call: [String]
        var no: [String], yes: [String]
    }

    private static let table: [AppLanguage: Words] = [
        .en: Words(stop: ["stop", "end session", "finish"], dontStop: ["don't stop", "dont stop", "do not stop"],
                   swap: ["swap", "switch", "take over", "change rescuer"], time: ["how long", "what time", "timer"],
                   status: ["how am i doing", "how's it going", "how is it going", "how do i look", "status", "feedback"],
                   call: ["call 911", "call for help", "call an ambulance", "call emergency", "ambulance", "call help"],
                   no: ["no", "nope", "nah", "not", "isn't", "isnt", "aren't", "doesn't", "nothing", "gasping", "gasps"],
                   yes: ["yes", "yeah", "yep", "yup", "responding", "breathing", "they are", "he is", "she is", "correct"]),
        .es: Words(stop: ["detente", "parar", "alto", "stop", "termina"], dontStop: ["no pares", "no parar", "sin parar"],
                   swap: ["cambio", "cambiar", "relevo", "relévame"], time: ["cuánto tiempo", "cuanto tiempo", "tiempo"],
                   status: ["cómo voy", "como voy", "cómo lo hago", "como lo hago", "qué tal", "que tal"],
                   call: ["llama", "llamar", "ambulancia", "emergencias", "ayuda"],
                   no: ["no", "nada", "jadea", "boquea"], yes: ["sí", "si", "responde", "respira", "claro"]),
        .fr: Words(stop: ["stop", "arrête", "arrêter", "arrete", "termine"], dontStop: ["n'arrête pas", "arrête pas", "sans arrêt"],
                   swap: ["change", "changer", "relais", "relève", "remplace"], time: ["combien de temps", "temps"],
                   status: ["comment je fais", "comment ça va", "comment ca va", "je fais bien"],
                   call: ["appelle", "appeler", "ambulance", "secours", "samu"],
                   no: ["non", "pas", "rien", "halète", "suffoque"], yes: ["oui", "ouais", "répond", "respire"]),
        .zh: Words(stop: ["停止", "停下", "停", "结束"], dontStop: ["不要停", "别停", "不停"],
                   swap: ["换人", "交换", "换一下", "替换"], time: ["多久", "多长时间", "几分钟", "时间"],
                   status: ["怎么样", "做得对", "做得好吗"], call: ["打电话", "呼叫", "急救", "救护车", "120"],
                   no: ["没", "不", "喘"], yes: ["是", "有", "对", "嗯", "在呼吸"]),
        .ko: Words(stop: ["멈춰", "그만", "정지", "스톱", "종료"], dontStop: ["멈추지 마", "멈추지마", "계속"],
                   swap: ["교대", "바꿔", "교체"], time: ["얼마나", "몇 분", "시간"],
                   status: ["어때", "잘하고", "괜찮아"], call: ["전화", "119", "구급차", "신고"],
                   no: ["아니", "안 ", "없어", "없어요", "못", "헐떡"], yes: ["네", "예", "응", "있어", "쉬어", "맞아"]),
        .ja: Words(stop: ["止めて", "やめて", "ストップ", "停止", "とめて", "終了"], dontStop: ["止めないで", "やめないで"],
                   swap: ["交代", "代わって", "かわって"], time: ["どのくらい", "何分", "時間"],
                   status: ["どう", "調子", "大丈夫"], call: ["電話", "119", "救急車", "通報"],
                   no: ["いいえ", "ない", "してない", "あえいで", "あえぎ"], yes: ["はい", "うん", "ええ", "している", "してる", "あります"]),
        .hi: Words(stop: ["रुको", "रोको", "बंद करो", "स्टॉप", "stop"], dontStop: ["मत रुको", "रुकना मत"],
                   swap: ["बदलो", "बदल", "स्वैप", "swap"], time: ["कितना समय", "कितनी देर", "समय"],
                   status: ["कैसा कर", "कैसे कर", "ठीक है क्या"], call: ["कॉल", "फोन", "फ़ोन", "एम्बुलेंस", "112", "108"],
                   no: ["नहीं", "नही", "ना"], yes: ["हाँ", "हां", "हा", "जी", "सांस ले"]),
    ]

    /// `expectingAnswer`: the emergency check is waiting for yes or no.
    static func match(_ text: String, lang: AppLanguage, expectingAnswer: Bool) -> VoiceCommand? {
        guard let w = table[lang] else { return nil }
        let t = " " + text.lowercased().replacingOccurrences(of: "’", with: "'") + " "
        let tokens = Set(t.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" }).map(String.init))
        // Languages without spaces (and Korean/Hindi, whose words take particles and endings) match
        // substrings; elsewhere single words must match whole, so "no" doesn't fire on "know".
        let substrings = lang.unspaced || lang == .ko || lang == .hi
        func has(_ phrases: [String]) -> Bool {
            phrases.contains { p in substrings || p.contains(" ") || p.contains("'") ? t.contains(p) : tokens.contains(p) }
        }
        if expectingAnswer {
            if has(w.no) { return .no }
            if has(w.yes) { return .yes }
        }
        if has(w.call) { return .call }
        if has(w.swap) { return .swap }
        if has(w.status) { return .status }
        if has(w.time) { return .time }
        if has(w.stop) && !has(w.dontStop) { return .stop }
        return nil
    }
}

/// The live request, shared with the audio thread that feeds it.
private nonisolated final class RequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    func set(_ r: SFSpeechAudioBufferRecognitionRequest?) { lock.withLock { request = r } }
    func append(_ b: AVAudioPCMBuffer) { lock.withLock { request?.append(b) } }
}

/// Continuous on-device speech recognition that reports each new phrase once.
@MainActor
final class VoiceListener {
    enum State: Equatable { case off, unavailable, listening }

    private(set) var state: State = .off
    /// New words heard since the last report; return true if they were a command (consumes them).
    var onPhrase: ((String) -> Bool)?
    /// True while the coach is speaking (and briefly after), so its own voice is ignored.
    var isEchoWindow: () -> Bool = { false }

    private let engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private let box = RequestBox()
    private var task: SFSpeechRecognitionTask?
    private var consumed = 0
    private var taskStarted = Date.distantPast
    private var generation = 0

    func start(language: AppLanguage) async {
        stop()
        guard await Self.authorize() else { state = .unavailable; return }
        guard let r = SFSpeechRecognizer(locale: language.locale), r.isAvailable else { state = .unavailable; return }
        recognizer = r
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { state = .unavailable; return }
        let box = box
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { @Sendable buffer, _ in
            box.append(buffer) // audio thread
        }
        engine.prepare()
        do { try engine.start() } catch { input.removeTap(onBus: 0); state = .unavailable; return }
        state = .listening
        newTask()
    }

    func stop() {
        generation += 1
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        box.set(nil)
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        if state == .listening { state = .off }
    }

    /// Recognition tasks end after a minute or a long silence; keep a fresh one running.
    private func newTask() {
        guard state == .listening, let recognizer else { return }
        task?.cancel()
        request?.endAudio()
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        req.taskHint = .confirmation
        request = req
        box.set(req)
        consumed = 0
        taskStarted = Date()
        generation += 1
        let gen = generation
        task = recognizer.recognitionTask(with: req) { @Sendable [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let done = error != nil || result?.isFinal == true
            Task { @MainActor in self?.handle(text: text, done: done, gen: gen) }
        }
    }

    private func handle(text: String?, done: Bool, gen: Int) {
        guard gen == generation else { return }
        if let text, text.count > consumed {
            if isEchoWindow() {
                consumed = text.count // the coach talking; skip it
            } else {
                let fresh = String(text.dropFirst(consumed))
                if onPhrase?(fresh) == true {
                    // Start over so the same words can't fire twice.
                    newTask()
                    return
                }
            }
        }
        if done || Date().timeIntervalSince(taskStarted) > 50 { newTask() }
    }

    private static func authorize() async -> Bool {
        let speech = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { @Sendable s in c.resume(returning: s == .authorized) }
        }
        guard speech else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }
}
