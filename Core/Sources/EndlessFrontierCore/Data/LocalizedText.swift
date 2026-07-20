import Foundation

/// The languages the game ships content in. `en` is the source of truth and
/// the fallback for any string a translation hasn't covered yet.
public enum GameLanguage: String, Codable, Sendable, CaseIterable {
    case en
    case cs

    /// The best-matching game language for a locale, defaulting to English.
    public static func matching(_ locale: Locale) -> GameLanguage {
        let code = locale.language.languageCode?.identifier ?? "en"
        return GameLanguage(rawValue: code) ?? .en
    }
}

/// A piece of player-facing text that may be translated. Content JSON can give
/// either a bare string (English, during incremental translation) or a
/// `{ "en": …, "cs": … }` object. Missing languages fall back to English, then
/// to any available value, so a half-translated file always renders.
///
/// This keeps `Core` locale-agnostic: engines pass `LocalizedText` around and
/// the app resolves it for the player's language at the edge.
public struct LocalizedText: Codable, Sendable, Equatable, Hashable, ExpressibleByStringLiteral {
    /// Per-language strings. Always contains at least an `en` entry.
    public private(set) var values: [GameLanguage: String]

    public init(_ english: String) {
        values = [.en: english]
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }

    public init(values: [GameLanguage: String]) {
        // Guarantee an English anchor so `resolve` always has a fallback.
        if values[.en] == nil, let anyValue = values.first?.value {
            var v = values
            v[.en] = anyValue
            self.values = v
        } else {
            self.values = values.isEmpty ? [.en: ""] : values
        }
    }

    /// The string for a language, falling back to English, then to anything.
    public func resolve(_ language: GameLanguage = .en) -> String {
        values[language] ?? values[.en] ?? values.first?.value ?? ""
    }

    /// Convenience: resolve for a `Locale`.
    public func resolve(for locale: Locale) -> String {
        resolve(GameLanguage.matching(locale))
    }

    // MARK: - Codable

    public init(from decoder: Decoder) throws {
        // Accept a bare string…
        if let single = try? decoder.singleValueContainer(),
           let text = try? single.decode(String.self) {
            self.init(text)
            return
        }
        // …or a { language: string } object.
        let c = try decoder.container(keyedBy: LanguageKey.self)
        var parsed: [GameLanguage: String] = [:]
        for language in GameLanguage.allCases {
            if let text = try c.decodeIfPresent(String.self, forKey: LanguageKey(language.rawValue)) {
                parsed[language] = text
            }
        }
        guard !parsed.isEmpty else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "LocalizedText must be a string or a { language: string } object"
            ))
        }
        self.init(values: parsed)
    }

    public func encode(to encoder: Encoder) throws {
        // A single-language (English-only) value encodes as a bare string so
        // untranslated content stays compact and diff-friendly.
        if values.count == 1, let english = values[.en] {
            var single = encoder.singleValueContainer()
            try single.encode(english)
            return
        }
        var c = encoder.container(keyedBy: LanguageKey.self)
        for (language, text) in values.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            try c.encode(text, forKey: LanguageKey(language.rawValue))
        }
    }

    private struct LanguageKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(_ stringValue: String) { self.stringValue = stringValue }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}
