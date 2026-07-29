import SwiftUI
import EndlessFrontierCore

/// A town of sixty, drawn as a town.
///
/// Every colonist has always been drawn as a full figure — head, tunic, legs, a
/// tool in the working hand — at every zoom. That is exactly right when you are
/// pushed in on the square watching a smith at his anvil, and exactly wrong
/// when you are looking at the whole valley: sixty people at eleven pixels each
/// is not a town, it is a smear, and the one thing you actually want to read
/// from up there — *where are my people and what are they doing* — is the one
/// thing you cannot.
///
/// So the canvas draws people at two levels of detail. Pushed in, they are
/// people. Pulled back, colonists standing near one another collapse into a
/// **group mark**: one cluster with a headcount and the colour of whatever
/// trade most of them are on, so the valley reads as "eight at the wood, five
/// at the quarry, the rest in town" at a glance. Push the camera in and the
/// group resolves into the people it was made of.
///
/// Purely presentational. Grouping is a function of the poses the motion layer
/// already produces; nothing here touches the simulation.
enum SettlementCrowd {

    /// Below this zoom, people are drawn as groups rather than as individuals.
    static let detailZoom: CGFloat = 1.5
    /// How near two colonists have to be to count as one group, in normalised
    /// map units. Roughly a building's width — people at the same place, not
    /// people in the same half of the valley.
    static let clusterRadius: Double = 0.045
    /// A cluster smaller than this is drawn as its people anyway: two figures
    /// read better than a mark that says "2".
    static let minimumGroup = 3

    /// One group of colonists standing together.
    struct Cluster {
        var position: LocalPoint
        var count: Int
        /// What most of them are doing, for the colour and the icon.
        var trade: WorkKind
        /// Whether anyone in it is hurt — the one thing worth escalating from
        /// a group mark, because it is the thing you would want to look at.
        var anyHurt: Bool
        /// The people it is made of, so a tap can still find somebody.
        var members: [UUID]
    }

    /// Whether the camera is close enough to draw people as people.
    static func showsIndividuals(zoom: CGFloat) -> Bool { zoom >= detailZoom }

    /// Gathers poses into clusters.
    ///
    /// A single pass in the order the poses arrive: each colonist joins the
    /// first cluster they are near enough to, or starts one. Deliberately not a
    /// proper clustering — this is a drawing decision made thirty times a
    /// second, and "near the first person who was already there" is both stable
    /// between frames and cheap.
    static func cluster(_ people: [(id: UUID, position: LocalPoint, trade: WorkKind, hurt: Bool)])
    -> [Cluster] {
        var clusters: [Cluster] = []
        var trades: [Int: [WorkKind: Int]] = [:]
        let r2 = clusterRadius * clusterRadius

        for person in people {
            var joined = false
            for i in clusters.indices {
                let dx = clusters[i].position.x - person.position.x
                let dy = clusters[i].position.y - person.position.y
                guard dx * dx + dy * dy <= r2 else { continue }
                // The cluster's place is the running mean of who is in it, so a
                // group sits among its people rather than on whoever arrived
                // first.
                let n = Double(clusters[i].count)
                clusters[i].position = LocalPoint(
                    x: (clusters[i].position.x * n + person.position.x) / (n + 1),
                    y: (clusters[i].position.y * n + person.position.y) / (n + 1))
                clusters[i].count += 1
                clusters[i].members.append(person.id)
                clusters[i].anyHurt = clusters[i].anyHurt || person.hurt
                trades[i, default: [:]][person.trade, default: 0] += 1
                joined = true
                break
            }
            guard !joined else { continue }
            trades[clusters.count] = [person.trade: 1]
            clusters.append(Cluster(position: person.position, count: 1,
                                    trade: person.trade, anyHurt: person.hurt,
                                    members: [person.id]))
        }

        // What most of each group is doing.
        for i in clusters.indices {
            if let common = trades[i]?.max(by: { $0.value < $1.value })?.key {
                clusters[i].trade = common
            }
        }
        return clusters
    }

    /// Draws one group: a knot of shoulders, a headcount, and the colour of
    /// whatever most of them are on.
    static func draw(
        _ context: inout GraphicsContext, cluster: Cluster, at c: CGPoint,
        time: Double, zoom: CGFloat
    ) {
        let shade = Theme.roleShade(cluster.trade)
        let s = (5.0 + min(4.0, CGFloat(cluster.count) * 0.35)) * zoom

        // The ground they stand on.
        context.fill(Path(ellipseIn: CGRect(x: c.x - s * 0.9, y: c.y + s * 0.15,
                                            width: s * 1.8, height: s * 0.5)),
                     with: .color(.black.opacity(0.26)))

        // Three or four overlapping shoulders — a crowd read at a distance is
        // heads and shoulders, not stick figures.
        let shown = min(4, max(2, cluster.count / 2))
        for i in 0..<shown {
            let spread = (CGFloat(i) - CGFloat(shown - 1) / 2) * s * 0.42
            let bob = CGFloat(sin(time * 1.6 + Double(i) * 1.3)) * s * 0.05
            let p = CGPoint(x: c.x + spread, y: c.y + bob)
            context.fill(Path { path in
                path.move(to: CGPoint(x: p.x - s * 0.32, y: p.y + s * 0.25))
                path.addQuadCurve(to: CGPoint(x: p.x + s * 0.32, y: p.y + s * 0.25),
                                  control: CGPoint(x: p.x, y: p.y - s * 0.42))
                path.closeSubpath()
            }, with: .color(shade.opacity(0.9)))
            context.fill(
                Path(ellipseIn: CGRect(x: p.x - s * 0.18, y: p.y - s * 0.72,
                                       width: s * 0.36, height: s * 0.36)),
                with: .color(Color(red: 0.84, green: 0.76, blue: 0.64)))
        }

        // The headcount, which is the whole reason to draw a group at all.
        let label = Text("\(cluster.count)")
            .font(.system(size: max(6, 7 * zoom), weight: .semibold))
            .foregroundStyle(Theme.text)
        context.draw(context.resolve(label), at: CGPoint(x: c.x, y: c.y - s * 1.05))

        // Somebody in there is hurt. Worth escalating out of a group mark,
        // because it is the thing you would push the camera in to look at.
        if cluster.anyHurt {
            let r = s * 0.22
            context.fill(Path(ellipseIn: CGRect(x: c.x + s * 0.6 - r, y: c.y - s * 0.9 - r,
                                                width: r * 2, height: r * 2)),
                         with: .color(Theme.danger.opacity(0.9)))
        }
    }
}
