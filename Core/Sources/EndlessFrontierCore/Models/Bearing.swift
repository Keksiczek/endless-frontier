import Foundation

/// **Which way the world is, from where you are standing.**
///
/// The world map knows exactly where everybody is — every region has a
/// `HexCoord` and every tribe and settlement sits in one. The local map knew
/// none of it. A raid picked its line with `rng.nextUnit() * 2 * .pi` and a
/// trader picked one of four edges at random, so the tribe you can see to the
/// north on the world map came over your southern fence, and the caravan you
/// watched cross three hexes eastward walked in from the west.
///
/// It is the shape this repository keeps finding: **the information existed on
/// one side and the other side invented its own.** This is the conversion that
/// joins them, and it is one function so the raid, the trader and the caravan
/// cannot disagree about where north is.
public enum Bearing {

    /// Axial hex coordinates to a flat plane, in the same orientation
    /// `HexLayout` draws the world map in — pointy-top, `q` running east and
    /// `r` running down-and-east.
    ///
    /// Only the *direction* between two of these is ever used, so the scale is
    /// arbitrary and the constants are the standard axial-to-cartesian ones.
    public static func plane(_ coord: HexCoord) -> (x: Double, y: Double) {
        let x = Double(coord.q) + Double(coord.r) / 2
        let y = Double(coord.r) * 0.866_025_4      // √3/2
        return (x, y)
    }

    /// The angle, in radians, pointing from `home` out toward `origin` — the
    /// line something coming *from* `origin` arrives along.
    ///
    /// Returns nil for two things in the same hex, because a party from your
    /// own region has no bearing to come in on and a caller should fall back to
    /// its own roll rather than being handed an arbitrary east.
    public static func angle(from home: HexCoord, toward origin: HexCoord) -> Double? {
        guard home != origin else { return nil }
        let a = plane(home), b = plane(origin)
        let dx = b.x - a.x, dy = b.y - a.y
        guard dx * dx + dy * dy > 1e-9 else { return nil }
        return atan2(dy, dx)
    }

    /// The bearing a party from `origin` arrives on at `home`, both named by
    /// the region they sit in. Nil when either has no place on the map, or
    /// when they share one.
    ///
    /// The convenience the three call sites actually want: they hold ids, not
    /// coordinates, and looking a region up is the step each of them would
    /// otherwise write for itself.
    public static func angle(
        fromRegion home: UUID?, towardRegion origin: UUID?, in state: WorldState
    ) -> Double? {
        guard let home, let origin, home != origin,
              let a = state.regions.first(where: { $0.id == home }),
              let b = state.regions.first(where: { $0.id == origin })
        else { return nil }
        return angle(from: a.coord, toward: b.coord)
    }

    /// Where on the edge of a local map something arriving along `angle` first
    /// appears.
    ///
    /// The local map is the unit square, so this is the point where the ray
    /// from the middle along `angle` leaves it, pulled a little inside the
    /// border so an arrival is drawn on the map rather than exactly on its
    /// rim. `spread` is a 0…1 roll that shifts it along the edge, so two
    /// parties from the same neighbour do not walk in single file — **0.5 is
    /// dead on the bearing**, which is what the default has to be or an
    /// unspread arrival is quietly a quarter of a map off its own line.
    public static func edgePoint(along angle: Double, spread: Double = 0.5) -> LocalPoint {
        let dx = cos(angle), dy = sin(angle)
        // How far the ray travels before it hits a side. The larger component
        // decides which side that is.
        let scale = 0.5 / max(abs(dx), abs(dy))
        let inset = 0.96      // just inside the border
        let jitter = (spread - 0.5) * 0.5
        // The shift runs *across* the arrival line, so it slides along the edge
        // rather than in and out of it.
        let x = 0.5 + dx * scale * inset - dy * jitter
        let y = 0.5 + dy * scale * inset + dx * jitter
        return LocalPoint(x: min(0.98, max(0.02, x)), y: min(0.98, max(0.02, y)))
    }
}
