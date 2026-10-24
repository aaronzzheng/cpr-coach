// In-app language: the coach's screen, voice and voice commands all follow one choice, which can
// be switched on the spot (say, handing the phone to a bystander who speaks Spanish). English
// strings are the keys; `Translations.swift` holds the other languages.
import Foundation

nonisolated enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case en, es, fr, zh, ko, ja, hi

    var id: String { rawValue }

    /// The language's own name, for the picker.
    var nativeName: String {
        switch self {
        case .en: "English"
        case .es: "Español"
        case .fr: "Français"
        case .zh: "中文"
        case .ko: "한국어"
        case .ja: "日本語"
        case .hi: "हिन्दी"
        }
    }

    /// For the English prompt to the on-device model ("Respond in …").
    var englishName: String {
        switch self {
        case .en: "English"
        case .es: "Spanish"
        case .fr: "French"
        case .zh: "Simplified Chinese"
        case .ko: "Korean"
        case .ja: "Japanese"
        case .hi: "Hindi"
        }
    }

    /// Locale for the speech voice and the speech recognizer.
    var locale: Locale {
        let id = switch self {
        case .en: "en-US"
        case .es: "es-ES"
        case .fr: "fr-FR"
        case .zh: "zh-CN"
        case .ko: "ko-KR"
        case .ja: "ja-JP"
        case .hi: "hi-IN"
        }
        return Locale(identifier: id)
    }

    /// Written without spaces between words, so keywords match as substrings.
    var unspaced: Bool { self == .zh || self == .ja }

    private static let key = "appLanguage"

    /// Read from anywhere (coach rules are nonisolated); only written on the main actor.
    nonisolated(unsafe) static var current: AppLanguage = {
        if let saved = UserDefaults.standard.string(forKey: key), let l = AppLanguage(rawValue: saved) { return l }
        let code = Locale.preferredLanguages.first.map { Locale(identifier: $0).language.languageCode?.identifier ?? "en" } ?? "en"
        return AppLanguage(rawValue: code) ?? .en
    }()

    @MainActor static func set(_ l: AppLanguage) {
        current = l
        UserDefaults.standard.set(l.rawValue, forKey: key)
    }
}

/// Translates an English string into the current language, then fills `%@` placeholders in order.
nonisolated func tr(_ english: String, _ args: String...) -> String {
    let lang = AppLanguage.current
    var s = lang == .en ? english : (translations[english]?[lang] ?? english)
    for a in args {
        guard let r = s.range(of: "%@") else { break }
        s.replaceSubrange(r, with: a)
    }
    return s
}

/// Decimal number in the current language's style (5.4 vs 5,4).
nonisolated func trNumber(_ x: Double, digits: Int) -> String {
    x.formatted(.number.precision(.fractionLength(digits)).locale(AppLanguage.current.locale))
}
