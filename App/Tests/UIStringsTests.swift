import Testing
import Foundation
@testable import EndlessFrontier

/// The content files have been audited for Czech since 2026-08-11 and
/// `ContentTests` keeps them that way — but it walks `GameData/*.json`, and the
/// app's own chrome is Swift. Nothing looked there, so seventeen English-only
/// strings sat in shipping panels: the whole items tab, the quest empty state,
/// the caravan blurb, "No active research".
///
/// This walks the source instead of trusting `AppStrings` to be complete, since
/// the failure mode is a `Text` that never reached `AppStrings` in the first
/// place.
///
/// **Four ways to translate a string exist in this app** — `AppStrings`,
/// `LocalizedText` from the Core, an inline `cs ? "…" : "…"`, and a local
/// `s(_:_:)` helper some views declare for themselves. This test accepts all
/// four rather than picking a winner; consolidating them is a separate job.
@Suite("Every line the app says reads in Czech as well as English")
struct UIStringsTests {

    /// Literals that are the same word in both languages, so wrapping them
    /// would add indirection and no translation. Keep this list short and make
    /// each entry argue for itself.
    static let sameInBothLanguages: Set<String> = [
        "Gini",   // the coefficient is "Gini" in Czech too
        // **The music credit, which must not be translated.** CC BY 4.0 asks
        // for this attribution in this wording, and a licence is not satisfied
        // by a paraphrase — translating it would be the one change here that
        // actually breaks something legal rather than merely reading oddly.
        // The sentence *around* it is translated; the credit itself is a
        // quotation. See docs/AUDIO-LICENCES.md.
        // Listed as it appears **in the source**, escapes and all: the scanner
        // reads the literal between the quotes without unescaping it.
        "\\\"Ambiment\\\" Kevin MacLeod (incompetech.com)"
    ]

    @Test("No panel greets a Czech player in English")
    func everyTextLiteralIsTranslated() throws {
        let sources = Self.sourcesDirectory
        let files = try Self.swiftFiles(under: sources)
        #expect(files.count > 40, "found \(files.count) sources — the path is probably wrong")

        var offenders: [String] = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for (number, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let line = String(line)
                guard !Self.alreadyTranslated(line) else { continue }
                for literal in Self.textLiterals(in: line) {
                    let bare = Self.strippingInterpolations(literal).trimmingCharacters(in: .whitespaces)
                    guard Self.readsAsProse(bare),
                          !Self.sameInBothLanguages.contains(bare) else { continue }
                    offenders.append("\(file.lastPathComponent):\(number + 1)  \"\(bare)\"")
                }
            }
        }
        #expect(offenders.isEmpty, """
            These \(offenders.count) strings ship in English only. Add them to \
            AppStrings (or one of the other three translation paths) rather than \
            widening the allowlist:
            \(offenders.joined(separator: "\n"))
            """)
    }

    // MARK: - Walking the source

    /// `#filePath` is baked in at compile time, so this resolves on the host
    /// even though the tests run in a simulator.
    static var sourcesDirectory: URL {
        URL(fileURLWithPath: #filePath)      // App/Tests/UIStringsTests.swift
            .deletingLastPathComponent()     // App/Tests
            .deletingLastPathComponent()     // App
            .appendingPathComponent("Sources")
    }

    static func swiftFiles(under root: URL) throws -> [URL] {
        guard let walker = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil) else { return [] }
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    // MARK: - Reading a line

    /// A `Text` whose argument is a translator call is fine whichever of the
    /// four mechanisms it uses.
    static func alreadyTranslated(_ line: String) -> Bool {
        line.contains("AppStrings")
            || line.contains("Text(s(")
            || line.contains("cs ?")
    }

    /// Every string literal that is the first argument of a `Text(`, with
    /// interpolations left in place for `strippingInterpolations` to remove.
    static func textLiterals(in line: String) -> [String] {
        var found: [String] = []
        let chars = Array(line)
        var i = 0
        while i < chars.count {
            guard chars[i] == "T", line.dropFirst(i).hasPrefix("Text(") else { i += 1; continue }
            var j = i + 5
            while j < chars.count, chars[j] == " " { j += 1 }
            guard j < chars.count, chars[j] == "\"" else { i += 1; continue }
            j += 1

            var literal = ""
            var depth = 0                       // inside \( … )
            var inNestedString = false
            while j < chars.count {
                let c = chars[j]
                if c == "\\", j + 1 < chars.count, chars[j + 1] == "(" {
                    literal.append("\\("); depth += 1; j += 2; continue
                }
                if c == "\\", j + 1 < chars.count {          // any other escape
                    literal.append(c); literal.append(chars[j + 1]); j += 2; continue
                }
                if depth > 0 {
                    if c == "\"" { inNestedString.toggle() }
                    else if !inNestedString, c == "(" { depth += 1 }
                    else if !inNestedString, c == ")" { depth -= 1 }
                    literal.append(c); j += 1; continue
                }
                if c == "\"" { break }                       // closed the literal
                literal.append(c); j += 1
            }
            found.append(literal)
            i = j + 1
        }
        return found
    }

    /// Drops `\( … )` so only the author's own words are judged. `"\(count)"`
    /// is not an English string; `"Mood \(n)"` is.
    static func strippingInterpolations(_ literal: String) -> String {
        var out = ""
        let chars = Array(literal)
        var i = 0
        while i < chars.count {
            if chars[i] == "\\", i + 1 < chars.count, chars[i + 1] == "(" {
                var depth = 1
                var inString = false
                i += 2
                while i < chars.count, depth > 0 {
                    let c = chars[i]
                    if inString {
                        if c == "\\" { i += 1 }
                        else if c == "\"" { inString = false }
                    } else if c == "\"" { inString = true }
                    else if c == "(" { depth += 1 }
                    else if c == ")" { depth -= 1 }
                    i += 1
                }
                continue
            }
            out.append(chars[i]); i += 1
        }
        return out
    }

    /// Two letters in a row is the line between a word and a symbol. It keeps
    /// units and ornaments out of the net — "×", "·", "%", and the single "z"
    /// of a sleeping colonist — without needing a list of them.
    static func readsAsProse(_ s: String) -> Bool {
        var run = 0
        for c in s {
            if c.isLetter, c.isASCII {
                run += 1
                if run >= 2 { return true }
            } else {
                run = 0
            }
        }
        return false
    }
}

/// **The first two minutes**, which the game did not have at all: a new player
/// was put in a village with a build bar and left to work out the tick rate,
/// the council, the food chain and the tappable world on their own.
@Suite("The introduction says the four things that are not guessable")
struct FirstRunTests {
    @Test("Both languages say the same number of things")
    func bothLanguagesAreComplete() {
        #expect(FirstRunView.Page.english.count == FirstRunView.Page.czech.count)
        #expect(FirstRunView.Page.english.count == 4)
    }

    /// The project ships nothing half-translated (`ContentTests` guards the
    /// game data; this is the app's own side of the same rule).
    @Test("Nothing in it is blank, and the Czech is not the English")
    func nothingIsUntranslated() {
        for (en, cs) in zip(FirstRunView.Page.english, FirstRunView.Page.czech) {
            #expect(!en.title.isEmpty && !en.body.isEmpty)
            #expect(!cs.title.isEmpty && !cs.body.isEmpty)
            #expect(en.title != cs.title, "'\(en.title)' was never translated")
            #expect(en.body != cs.body)
            #expect(en.symbol == cs.symbol, "the same page must carry the same mark in both")
        }
    }

    /// Each card exists to name one thing that costs an hour to learn the hard
    /// way. If a rewrite drops one, this says which.
    @Test("It still covers the tick, the council, the chain and the canvas")
    func itCoversWhatItIsFor() {
        let english = FirstRunView.Page.english.map { ($0.title + " " + $0.body).lowercased() }
        func mentions(_ words: [String]) -> Bool {
            english.contains { page in words.contains { page.contains($0) } }
        }
        #expect(mentions(["two real minutes", "tick"]), "the tick rate")
        #expect(mentions(["council"]), "that nobody is waiting for orders")
        #expect(mentions(["cook", "chain"]), "that food is a chain")
        #expect(mentions(["tap"]), "that the world answers")
    }
}
