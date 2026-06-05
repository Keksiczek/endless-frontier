import Foundation

/// The five core resources the player manages globally and per-settlement.
///
/// Raw values are stable string identifiers used in JSON game data
/// (buildings, events, tech costs). Never rename a raw value without
/// migrating the data files.
public enum ResourceType: String, Codable, Sendable, CaseIterable, Hashable {
    case food
    case materials
    case energy
    case knowledge
    case influence
}

/// A bag of resource amounts. Used both for mutable storage (settlements)
/// and for static game-data maps (building cost / production / consumption,
/// tech cost, choice cost, biome affinity).
///
/// Codable as a compact JSON object keyed by resource raw values, e.g.
/// `{ "food": 5, "materials": -2 }`. Zero-valued entries are omitted on
/// encode. This is why the type is used everywhere a resource-keyed map
/// appears in hand-authored data — a plain `[ResourceType: Double]` would
/// (per Swift's Codable rules for non-String keys) encode as a flat array.
///
/// Mutating helpers follow the project's immutability convention: they
/// return a new `Resources` rather than mutating in place.
public struct Resources: Codable, Sendable, Equatable, ExpressibleByDictionaryLiteral {
    public private(set) var amounts: [ResourceType: Double]

    public init(_ amounts: [ResourceType: Double] = [:]) {
        self.amounts = amounts
    }

    public init(dictionaryLiteral elements: (ResourceType, Double)...) {
        self.amounts = Dictionary(elements) { _, latest in latest }
    }

    /// Convenience initialiser giving every resource the same starting value.
    public static func uniform(_ value: Double) -> Resources {
        Resources(Dictionary(uniqueKeysWithValues: ResourceType.allCases.map { ($0, value) }))
    }

    public subscript(_ type: ResourceType) -> Double {
        get { amounts[type] ?? 0 }
        set { amounts[type] = newValue }
    }

    /// Returns a new ledger with `delta` applied to `type`.
    public func adding(_ delta: Double, to type: ResourceType) -> Resources {
        var copy = self
        copy[type] = copy[type] + delta
        return copy
    }

    /// Returns a new ledger with every value clamped to `[lower, upper]`.
    public func clamped(lower: Double, upper: Double) -> Resources {
        var copy = self
        for type in ResourceType.allCases {
            copy[type] = min(max(copy[type], lower), upper)
        }
        return copy
    }

    /// True if any resource is strictly below `threshold`.
    public func anyBelow(_ threshold: Double) -> Bool {
        ResourceType.allCases.contains { self[$0] < threshold }
    }

    /// Count of resources whose stored amount is negative (in deficit).
    public var deficitCount: Int {
        ResourceType.allCases.filter { self[$0] < 0 }.count
    }

    /// Compares by effective value, so a missing key and an explicit zero are
    /// equal (`Resources([.energy: 0]) == Resources()`). This keeps equality
    /// stable across the zero-stripping JSON encoding.
    public static func == (lhs: Resources, rhs: Resources) -> Bool {
        ResourceType.allCases.allSatisfy { lhs[$0] == rhs[$0] }
    }

    // MARK: - Codable (object keyed by resource raw value)

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode([String: Double].self)
        var parsed: [ResourceType: Double] = [:]
        for (key, value) in raw {
            guard let type = ResourceType(rawValue: key) else {
                throw DecodingError.dataCorruptedError(
                    in: try decoder.singleValueContainer(),
                    debugDescription: "Unknown resource key: \(key)"
                )
            }
            parsed[type] = value
        }
        self.amounts = parsed
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        let object = amounts
            .filter { $0.value != 0 }
            .reduce(into: [String: Double]()) { $0[$1.key.rawValue] = $1.value }
        try container.encode(object)
    }
}
