import Foundation

/// What the overlay's second line holds.
///
/// The raw values are the persisted setting strings and the labels shown in
/// Settings, matching how `LyricsLanguagePreference` and the theme enums are
/// stored elsewhere in the app.
public enum SecondaryLine: String, CaseIterable, Equatable {
    /// The upcoming lyric — the app's behaviour before bilingual support.
    case nextLine = "Next Line"
    case translation = "Chinese Translation"
    case romaji = "Romaji"
}
