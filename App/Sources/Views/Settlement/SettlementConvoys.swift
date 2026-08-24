import SwiftUI
import EndlessFrontierCore

/// Your own carts, on your own road.
///
/// A caravan has always been a real thing in the simulation — cargo, named
/// guards out of the sending town, several ticks on the road, and a chance of
/// being ambushed on the way — and it has never once been visible. A shipment
/// left as a line in a list and arrived as another one, so the most dangerous
/// journey anybody in the colony makes happened entirely off screen.
///
/// This draws the legs that cross *this* valley: a cart going out walks from
/// the square to the edge over the first stretch of its journey, and one coming
/// in walks from the edge to the square over the last. In between it is out in
/// country this map does not cover, which is exactly where it can be ambushed.
///
/// Purely presentational — position comes from `Caravan.progress` and nothing
/// here writes back.
enum SettlementConvoys {

    /// How much of a journey happens on the sending valley's own ground.
    static let outboundLeg = 0.22
    /// …and on the receiving one's.
    static let inboundLeg = 0.22

    static func draw(
        _ context: inout GraphicsContext, rect: CGRect, settlement: Settlement,
        caravans: [Caravan], map: LocalMap, time: Double, zoom: CGFloat
    ) {
        for caravan in caravans {
            guard let leg = position(of: caravan, for: settlement.id) else { continue }
            guard map.isExplored(leg.position) else { continue }
            cart(&context, at: SettlementRenderer.point(leg.position, in: rect),
                 load: caravan.load, guards: caravan.guards.count,
                 outbound: leg.outbound, raided: caravan.status != .traveling,
                 time: time, zoom: zoom, seed: seed(caravan.id))
        }
    }

    /// Where a caravan is on this settlement's ground, if it is on it at all.
    ///
    /// The road runs from the square to the edge the other town lies toward.
    /// Which edge is fixed per caravan rather than computed from the world map:
    /// the local map has no bearing on it, and a shipment that changed which
    /// way it left between frames would be worse than one that simply always
    /// leaves the same way.
    static func position(of caravan: Caravan, for settlementID: UUID)
    -> (position: LocalPoint, outbound: Bool)? {
        let heart = SettlementGeometry.heart
        let gate = gate(for: caravan.id)
        if caravan.originID == settlementID {
            let t = caravan.progress / outboundLeg
            guard t <= 1 else { return nil }
            return (interpolate(heart, gate, t: ease(t)), true)
        }
        if caravan.destinationID == settlementID {
            let remaining = 1 - caravan.progress
            let t = remaining / inboundLeg
            guard t <= 1 else { return nil }
            return (interpolate(heart, gate, t: ease(t)), false)
        }
        return nil
    }

    /// The edge a given caravan uses, stable per caravan.
    static func gate(for id: UUID) -> LocalPoint {
        let h = seed(id)
        let along = 0.15 + Double(h % 1000) / 1000 * 0.7
        switch Int(h / 1000) % 4 {
        case 0: return LocalPoint(x: along, y: 0.03)
        case 1: return LocalPoint(x: 0.97, y: along)
        case 2: return LocalPoint(x: along, y: 0.97)
        default: return LocalPoint(x: 0.03, y: along)
        }
    }

    // MARK: - Drawing

    /// A cart, its ox and its escort. Small, because it is one wagon and not a
    /// column, and marked when it has been in a fight.
    private static func cart(
        _ context: inout GraphicsContext, at c: CGPoint, load: CaravanCargo,
        guards: Int, outbound: Bool, raided: Bool, time: Double, zoom: CGFloat,
        seed: UInt64
    ) {
        let s = 4.0 * zoom
        let wood = Color(red: 0.46, green: 0.36, blue: 0.25)
        let goods = cargoColour(load)
        let phase = Double(seed % 997) / 997 * 6.28

        context.fill(Path(ellipseIn: CGRect(x: c.x - s * 0.9, y: c.y + s * 0.5,
                                            width: s * 1.8, height: s * 0.4)),
                     with: .color(.black.opacity(0.26)))
        // The bed of the wagon, and what is in it.
        let bed = CGRect(x: c.x - s * 0.75, y: c.y - s * 0.35, width: s * 1.5, height: s * 0.7)
        context.fill(Path(roundedRect: bed, cornerRadius: s * 0.12), with: .color(wood))
        context.fill(Path(roundedRect: CGRect(x: bed.minX + s * 0.15, y: bed.minY - s * 0.28,
                                              width: bed.width - s * 0.3, height: s * 0.4),
                          cornerRadius: s * 0.1),
                     with: .color(goods))
        // Two wheels, turning as it rolls.
        let spin = time * 3 + phase
        for side in [-1.0, 1.0] {
            let wheel = CGPoint(x: c.x + CGFloat(side) * s * 0.5, y: c.y + s * 0.42)
            let r = s * 0.26
            context.stroke(Path(ellipseIn: CGRect(x: wheel.x - r, y: wheel.y - r,
                                                  width: r * 2, height: r * 2)),
                           with: .color(Theme.boneDim.opacity(0.85)), lineWidth: 0.8)
            context.stroke(Path { p in
                p.move(to: CGPoint(x: wheel.x - CGFloat(cos(spin)) * r,
                                   y: wheel.y - CGFloat(sin(spin)) * r))
                p.addLine(to: CGPoint(x: wheel.x + CGFloat(cos(spin)) * r,
                                      y: wheel.y + CGFloat(sin(spin)) * r))
            }, with: .color(Theme.boneDim.opacity(0.6)), lineWidth: 0.6)
        }
        // The ox in the traces, ahead of the wagon in the direction of travel.
        let lead: CGFloat = outbound ? 1 : -1
        let ox = CGPoint(x: c.x + lead * s * 1.35, y: c.y + s * 0.05)
        context.fill(Path(ellipseIn: CGRect(x: ox.x - s * 0.42, y: ox.y - s * 0.3,
                                            width: s * 0.84, height: s * 0.56)),
                     with: .color(Color(red: 0.40, green: 0.34, blue: 0.28)))

        // The escort, walking alongside.
        for i in 0..<min(3, max(1, guards)) {
            let p = CGPoint(x: c.x - lead * s * (0.9 + CGFloat(i) * 0.55),
                            y: c.y + s * (0.1 + CGFloat(i % 2) * 0.4))
            let gait = CGFloat(sin(time * 5 + phase + Double(i))) * s * 0.22
            context.fill(Path(ellipseIn: CGRect(x: p.x - s * 0.2, y: p.y - s * 0.85,
                                                width: s * 0.4, height: s * 0.4)),
                         with: .color(Color(red: 0.82, green: 0.74, blue: 0.62)))
            var body = Path()
            body.move(to: CGPoint(x: p.x, y: p.y - s * 0.45))
            body.addLine(to: CGPoint(x: p.x, y: p.y + s * 0.1))
            body.move(to: CGPoint(x: p.x - s * 0.2 + gait, y: p.y + s * 0.6))
            body.addLine(to: CGPoint(x: p.x, y: p.y + s * 0.1))
            body.addLine(to: CGPoint(x: p.x + s * 0.2 - gait, y: p.y + s * 0.6))
            context.stroke(body, with: .color(Theme.roleShade(.trade)),
                           style: StrokeStyle(lineWidth: max(0.8, s * 0.2), lineCap: .round))
        }

        // It has been in a fight: the one thing about a journey you would want
        // to know at a glance.
        if raided {
            let r = s * 1.5
            context.stroke(
                Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                with: .color(Theme.danger.opacity(0.55 + 0.25 * sin(time * 4))),
                lineWidth: 1.1)
        }
    }

    static func cargoColour(_ load: CaravanCargo) -> Color {
        // A cart of goods is a cart of *things*, and things are the colour of
        // what they are made of rather than of a ledger column.
        switch load {
        case let .goods(item):
            switch item {
            case "wood", "timber_bundle": return Color(red: 0.55, green: 0.41, blue: 0.26)
            case "charcoal": return Color(red: 0.24, green: 0.22, blue: 0.21)
            case "rough_stone", "brick", "clay": return Color(red: 0.60, green: 0.55, blue: 0.49)
            case "iron_ore", "iron_ingot": return Color(red: 0.47, green: 0.49, blue: 0.53)
            default: return Color(red: 0.52, green: 0.50, blue: 0.48)
            }
        case .resource(let resource):
        switch resource {
        case .food: return Color(red: 0.78, green: 0.68, blue: 0.38)
        case .materials: return Color(red: 0.52, green: 0.50, blue: 0.48)
        case .knowledge: return Color(red: 0.58, green: 0.66, blue: 0.80)
        case .influence: return Color(red: 0.80, green: 0.62, blue: 0.34)
        case .energy: return Color(red: 0.72, green: 0.74, blue: 0.44)
            }
        }
    }

    // MARK: - Maths

    static func seed(_ id: UUID) -> UInt64 {
        var h: UInt64 = 0xCBF2_9CE4_8422_2325
        let b = id.uuid
        for byte in [b.0, b.1, b.2, b.3, b.4, b.5, b.6, b.7] {
            h = (h ^ UInt64(byte)) &* 0x0100_0000_01B3
        }
        return h
    }

    private static func interpolate(_ a: LocalPoint, _ b: LocalPoint, t: Double) -> LocalPoint {
        LocalPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    private static func ease(_ t: Double) -> Double {
        let c = min(1, max(0, t))
        return c * c * (3 - 2 * c)
    }
}
