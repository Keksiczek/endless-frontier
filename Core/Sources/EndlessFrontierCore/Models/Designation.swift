import Foundation

/// **A thing the player has pointed at and said: that one.**
///
/// Keks: *"vše drawn je there, ale pak na věci nejde klikat, vybírat je k akci
/// — max doufat, že se někdy něco stane a někdo k nim půjde."*
///
/// The canvas has been able to *hit* a tree, a rock or a heap of timber for a
/// while — `SettlementCanvasView.hitTest` walks all of them — and every one of
/// them answered with a label and nothing else. The colony chops the biggest
/// tree, mines the nearest seam and hauls whatever is closest, for ever, and
/// the player watches. That is a screensaver with statistics.
///
/// A designation is the smallest thing that turns watching into playing: it
/// does not order a *person* anywhere, it marks a **thing** as wanted, and the
/// engines that were already choosing targets choose the marked one first. So
/// nobody is pulled off their trade, nobody walks across the valley to obey,
/// and a mark nobody can reach is simply a mark that outlives the tick — which
/// is exactly how it behaves in the game this borrows from.
///
/// The rule it must not break: **the canvas never writes the simulation.** A
/// designation is placed by the view *model* (the same path that lays a road
/// or gives a battle order), stored on the settlement, and read by the engines.
/// The renderer only draws the mark.
public struct Designation: Codable, Sendable, Equatable, Identifiable {

    /// What has been marked. Ids, never positions: a heap that is carried
    /// halfway in has moved, and a mark that meant "the thing at these
    /// coordinates" would be pointing at grass.
    public enum Target: Codable, Sendable, Equatable, Hashable {
        case tree(Int)
        case rock(Int)
        case pile(UUID)
        case animal(UUID)
    }

    /// What is wanted of it. One kind per target — "fell this tree" is the
    /// only thing anybody wants of a tree — so this is really a label for the
    /// order rather than a choice, and it is stored because a *card* has to
    /// say it out loud.
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case fell      // a tree
        case mine      // a rock
        case haul      // a heap lying about
        case hunt      // a beast

        public var label: LocalizedText {
            switch self {
            case .fell: return LocalizedText(values: [.en: "Fell it", .cs: "Pokácet"])
            case .mine: return LocalizedText(values: [.en: "Break it", .cs: "Vylámat"])
            case .haul: return LocalizedText(values: [.en: "Carry it in", .cs: "Odnést"])
            case .hunt: return LocalizedText(values: [.en: "Hunt it", .cs: "Ulovit"])
            }
        }

        /// What the colony is told once it is marked — present tense, because
        /// this is a standing want rather than an event.
        public var standing: LocalizedText {
            switch self {
            case .fell: return LocalizedText(values: [
                .en: "Marked for felling", .cs: "Označeno k pokácení"])
            case .mine: return LocalizedText(values: [
                .en: "Marked to be broken", .cs: "Označeno k vylámání"])
            case .haul: return LocalizedText(values: [
                .en: "Marked to be carried in", .cs: "Označeno k odnesení"])
            case .hunt: return LocalizedText(values: [
                .en: "Marked for the hunt", .cs: "Označeno k ulovení"])
            }
        }

        /// The kind of order the target admits. A tree is felled and a beast
        /// is hunted; there is nothing to choose.
        public static func forTarget(_ target: Target) -> Kind {
            switch target {
            case .tree: return .fell
            case .rock: return .mine
            case .pile: return .haul
            case .animal: return .hunt
            }
        }
    }

    public let id: UUID
    public let target: Target
    public let kind: Kind
    /// When it was marked, so the oldest order is worked first and a mark can
    /// be shown as "asked for a while ago".
    public let placedTick: Int

    public init(id: UUID = UUID(), target: Target, kind: Kind? = nil, placedTick: Int) {
        self.id = id
        self.target = target
        self.kind = kind ?? Kind.forTarget(target)
        self.placedTick = placedTick
    }
}
