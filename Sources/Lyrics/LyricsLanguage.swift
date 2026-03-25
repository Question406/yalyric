import Foundation
import NaturalLanguage

enum LyricsLanguagePreference: String, CaseIterable {
    case auto = "Auto (match song language)"
    case any = "Any (first available)"
    case en = "English"
    case ja = "Japanese"
    case ko = "Korean"
    case zh = "Chinese"
    case es = "Spanish"
    case fr = "French"
    case de = "German"
    case pt = "Portuguese"

    /// The NLLanguage code, or nil for auto/any
    var nlLanguage: NLLanguage? {
        switch self {
        case .auto, .any: return nil
        case .en: return .english
        case .ja: return .japanese
        case .ko: return .korean
        case .zh: return .simplifiedChinese
        case .es: return .spanish
        case .fr: return .french
        case .de: return .german
        case .pt: return .portuguese
        }
    }
}

struct LyricsLanguageDetector {
    /// Detect the dominant language of lyrics text
    static func detect(_ text: String) -> NLLanguage? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage
    }

    /// Check if lyrics match the desired language preference
    static func matches(lyrics: Lyrics, preference: LyricsLanguagePreference, trackName: String = "", trackArtist: String = "") -> Bool {
        switch preference {
        case .any:
            return true
        case .auto:
            // Detect language from track name/artist and match against lyrics
            let trackText = "\(trackName) \(trackArtist)"
            guard let trackLang = detect(trackText) else { return true }
            let lyricsText = lyrics.lines.prefix(10).map(\.text).joined(separator: " ")
            guard let lyricsLang = detect(lyricsText) else { return true }
            return isCompatibleLanguage(track: trackLang, lyrics: lyricsLang)
        default:
            guard let desired = preference.nlLanguage else { return true }
            let lyricsText = lyrics.lines.prefix(10).map(\.text).joined(separator: " ")
            guard let detected = detect(lyricsText) else { return true }
            return isCompatibleLanguage(track: desired, lyrics: detected)
        }
    }

    /// Check if two languages are compatible (handles zh variants, etc.)
    private static func isCompatibleLanguage(track: NLLanguage, lyrics: NLLanguage) -> Bool {
        if track == lyrics { return true }

        // Chinese variants are compatible
        let chineseVariants: Set<NLLanguage> = [.simplifiedChinese, .traditionalChinese]
        if chineseVariants.contains(track) && chineseVariants.contains(lyrics) { return true }

        return false
    }
}
