import Foundation
import Testing
@testable import EndlessFrontierCore

@Suite("LocalizedText")
struct LocalizedTextTests {
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    @Test("Decodes a bare string as English")
    func bareString() throws {
        let text = try decoder.decode(LocalizedText.self, from: Data("\"Hello\"".utf8))
        #expect(text.resolve(.en) == "Hello")
        #expect(text.resolve(.cs) == "Hello")   // falls back to English
    }

    @Test("Decodes a per-language object")
    func languageObject() throws {
        let json = #"{"en": "Council", "cs": "Sněm"}"#
        let text = try decoder.decode(LocalizedText.self, from: Data(json.utf8))
        #expect(text.resolve(.en) == "Council")
        #expect(text.resolve(.cs) == "Sněm")
    }

    @Test("A missing language falls back to English")
    func partialTranslation() throws {
        let json = #"{"en": "Temple"}"#
        let text = try decoder.decode(LocalizedText.self, from: Data(json.utf8))
        #expect(text.resolve(.cs) == "Temple")
    }

    @Test("A Czech-only object still anchors on English for fallback")
    func czechOnly() throws {
        let json = #"{"cs": "Kronika"}"#
        let text = try decoder.decode(LocalizedText.self, from: Data(json.utf8))
        #expect(text.resolve(.cs) == "Kronika")
        #expect(text.resolve(.en) == "Kronika")   // anchored so nothing renders empty
    }

    @Test("Round-trips: English-only stays a bare string, translations expand")
    func roundTrip() throws {
        let english = LocalizedText("Farm")
        let englishData = try encoder.encode(english)
        #expect(String(decoding: englishData, as: UTF8.self) == "\"Farm\"")

        let bilingual = LocalizedText(values: [.en: "Farm", .cs: "Statek"])
        let bilingualData = try encoder.encode(bilingual)
        let reDecoded = try decoder.decode(LocalizedText.self, from: bilingualData)
        #expect(reDecoded == bilingual)
    }

    @Test("Resolves for a Locale")
    func localeResolution() {
        let text = LocalizedText(values: [.en: "Season", .cs: "Období"])
        #expect(text.resolve(for: Locale(identifier: "cs_CZ")) == "Období")
        #expect(text.resolve(for: Locale(identifier: "en_US")) == "Season")
        #expect(text.resolve(for: Locale(identifier: "de_DE")) == "Season")   // unknown → English
    }

    @Test("String literal initialisation")
    func stringLiteral() {
        let text: LocalizedText = "Outpost"
        #expect(text.resolve() == "Outpost")
    }
}
