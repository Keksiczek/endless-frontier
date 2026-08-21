import Foundation

/// Layer 3 — the narrator seam.
///
/// A narrator is handed a `ChapterSnapshot` and gives back prose. That is the
/// whole of it, and the narrowness is the point: the layer above the
/// simulation may **never** write `WorldState`, is never handed one, and
/// nothing it returns feeds back into the world. See
/// `docs/architecture/LAYERS.md` and `docs/CHRONICLE.md`.
///
/// `async` because the seat this protocol is holding open is a language model —
/// on-device or on localhost. `StubNarrator` ignores that and answers at once.
public protocol NarratorProtocol: Sendable {
    /// Whether this narrator can be asked at all. `StubNarrator` is always
    /// available; a model-backed one may not be. The flag exists so the game
    /// can **offer** a richer narrator, never so it can require one — the rule
    /// is offline-first, and a colony on a plane must read the same annals as
    /// a colony at home.
    var isAvailable: Bool { get }

    /// Prose for one chapter, or `nil` if this narrator has nothing to say.
    /// A `nil` is not an error and is never shown to the player as one: the
    /// caller falls back to the stub.
    func narrate(_ chapter: ChapterSnapshot, language: GameLanguage) async -> String?
}
