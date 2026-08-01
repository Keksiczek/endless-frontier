import Foundation

/// The colony's standing orders.
///
/// At sixty souls nobody wants to click each colonist. Every lever the game
/// had was per-person: this pawn's trade, that party's roster, and a famine you
/// answered by opening sixty inspectors. The pawn screen is for *looking at
/// somebody* — how they are, what they carry, who they sleep beside. What the
/// hands of a town do is a rule you set once and the engine keeps.
///
/// Three rules, and each one is a real lever rather than a preference:
///
/// - **Trades.** A weight per kind of work, `.off` through `.priority`. The
///   labour engine's own quotas are the baseline and this scales them, so a
///   colony can be told *we are a mining town* and stay one as people are born,
///   come of age and die. `.off` means the auto-assigner never picks it at all.
/// - **Rations.** How much of a meal a meal is. Short rations stretch the
///   granary through a bad winter and everybody knows it; a feast costs food
///   and buys back the mood.
/// - **The roster for parties.** Whether an expedition may take hands off the
///   trades you marked as priority, or must make do with whoever is spare.
///
/// Every field decodes-if-present with the behaviour the game had before the
/// policy existed, so an old save loads into "no standing orders" and plays
/// exactly as it did.
public struct ColonyPolicy: Codable, Sendable, Equatable {

    /// How hard the colony leans on a kind of work.
    public enum TradeStance: String, Codable, Sendable, CaseIterable {
        case off        // nobody, ever — the auto-assigner skips it
        case low
        case normal     // whatever the labour engine would do on its own
        case high
        case priority

        /// What the labour engine's own quota share is multiplied by.
        public var weight: Double {
            switch self {
            case .off: return 0
            case .low: return 0.45
            case .normal: return 1
            case .high: return 1.7
            case .priority: return 2.8
            }
        }

        public var label: LocalizedText {
            switch self {
            case .off: return LocalizedText(values: [.en: "None", .cs: "Nikdo"])
            case .low: return LocalizedText(values: [.en: "Few", .cs: "Málo"])
            case .normal: return LocalizedText(values: [.en: "Normal", .cs: "Běžně"])
            case .high: return LocalizedText(values: [.en: "Many", .cs: "Hodně"])
            case .priority: return LocalizedText(values: [.en: "Priority", .cs: "Přednostně"])
            }
        }
    }

    /// How much of a meal a meal is.
    public enum Ration: String, Codable, Sendable, CaseIterable {
        case famine     // half a meal. It keeps people alive and nothing more.
        case short
        case full       // what the colony ate before there was a policy
        case feast

        /// What a single meal costs the granary, against `foodPerMeal`.
        public var foodPerMeal: Double {
            switch self {
            case .famine: return 0.50
            case .short: return 0.74
            case .full: return 1
            case .feast: return 1.32
            }
        }

        /// How much hunger a meal of this size puts back. Deliberately *less*
        /// reduced than the food it costs: short rations are a saving, not a
        /// free lunch, and a colony on half a meal eats twice as often.
        ///
        /// The gap between the two numbers is the whole lever. At 0.50 food for
        /// 0.70 hunger, famine rations stretch a granary about forty per cent
        /// further — enough that a colony reaches for them in a bad winter.
        /// Closer together than that and the menu is decoration: the first
        /// version bought eight ticks and nobody would ever have used it.
        public var hungerPerMeal: Double {
            switch self {
            case .famine: return 0.70
            case .short: return 0.86
            case .full: return 1
            case .feast: return 1.10
            }
        }

        /// What eating like this does to the mood, per colonist.
        public var moodEffect: Double {
            switch self {
            case .famine: return -9
            case .short: return -4
            case .full: return 0
            case .feast: return 3
            }
        }

        public var label: LocalizedText {
            switch self {
            case .famine: return LocalizedText(values: [.en: "Famine rations", .cs: "Hladové dávky"])
            case .short: return LocalizedText(values: [.en: "Short rations", .cs: "Krácené dávky"])
            case .full: return LocalizedText(values: [.en: "Full rations", .cs: "Plné dávky"])
            case .feast: return LocalizedText(values: [.en: "Plenty", .cs: "Hojnost"])
            }
        }

        public var detail: LocalizedText {
            switch self {
            case .famine: return LocalizedText(values: [
                .en: "Half a meal. It keeps people alive and they know it.",
                .cs: "Půl porce. Lidi to udrží naživu — a oni to vědí."])
            case .short: return LocalizedText(values: [
                .en: "Enough to work on. The granary lasts a season longer.",
                .cs: "Na práci to stačí. Sýpka vydrží o sezónu déle."])
            case .full: return LocalizedText(values: [
                .en: "What people expect. Nobody remarks on it.",
                .cs: "Co lidi čekají. Nikdo to nekomentuje."])
            case .feast: return LocalizedText(values: [
                .en: "More than anyone needs, and it shows in the hall.",
                .cs: "Víc, než kdo potřebuje — a v síni je to znát."])
            }
        }
    }

    /// Who an expedition may take.
    public enum Roster: String, Codable, Sendable, CaseIterable {
        /// Anyone fit and free — what the game did before the policy existed.
        case anyone
        /// Never off a trade the colony has marked `.high` or `.priority`: the
        /// mines stay manned even when the ruins are calling.
        case spareHands
        /// Nobody. The colony does not send parties out at all.
        case nobody

        public var label: LocalizedText {
            switch self {
            case .anyone: return LocalizedText(values: [.en: "Anyone fit", .cs: "Kdokoli schopný"])
            case .spareHands: return LocalizedText(values: [.en: "Spare hands only", .cs: "Jen volné ruce"])
            case .nobody: return LocalizedText(values: [.en: "Nobody leaves", .cs: "Nikdo neodchází"])
            }
        }
    }

    /// Per-trade standing orders. Absent means `.normal`, so the default policy
    /// is an empty dictionary and behaves exactly like no policy at all.
    public var trades: [WorkKind: TradeStance]
    public var ration: Ration
    public var roster: Roster

    public init(trades: [WorkKind: TradeStance] = [:],
                ration: Ration = .full,
                roster: Roster = .anyone) {
        self.trades = trades
        self.ration = ration
        self.roster = roster
    }

    /// The standing order for a trade.
    public func stance(_ work: WorkKind) -> TradeStance { trades[work] ?? .normal }

    /// A copy with one trade's order changed. Orders that say `.normal` are
    /// dropped rather than stored, so "no standing orders" stays one value and
    /// two policies that mean the same thing compare equal.
    public func setting(_ work: WorkKind, to stance: TradeStance) -> ColonyPolicy {
        var copy = self
        if stance == .normal {
            copy.trades.removeValue(forKey: work)
        } else {
            copy.trades[work] = stance
        }
        return copy
    }

    /// Whether the player has said anything at all. Drives the "standing orders"
    /// badge: a colony under no orders should not claim to be under any.
    public var isDefault: Bool {
        trades.isEmpty && ration == .full && roster == .anyone
    }

    /// The trades the colony has said it will not give up.
    public var protectedTrades: Set<WorkKind> {
        Set(trades.filter { $0.value == .high || $0.value == .priority }.keys)
    }

    // MARK: - Codable (decode-if-present: an old save has no orders)

    private enum CodingKeys: String, CodingKey { case trades, ration, roster }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        trades = try c.decodeIfPresent([WorkKind: TradeStance].self, forKey: .trades) ?? [:]
        ration = try c.decodeIfPresent(Ration.self, forKey: .ration) ?? .full
        roster = try c.decodeIfPresent(Roster.self, forKey: .roster) ?? .anyone
    }
}
