import SwiftUI
import EndlessFrontierCore

/// What a battle did, made legible after the fact.
///
/// The canvas plays a raid out — a band closing on the walls, a volley, the
/// clash — but it plays over one real minute and only if you happen to be
/// watching. A fight where someone died should not be missable. This reads the
/// same `BattleLog` the canvas animates and lays out its arc and its cost, so a
/// battle leaves a record you can actually read: who came, how it broke, who
/// fell. Strictly a view of `settlement.lastBattle`; it writes nothing back.
struct BattleReportCard: View {
    let battle: BattleLog
    let onClose: () -> Void

    private var cs: Bool { AppStrings.language == .cs }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            engagementLine
            if !beats.isEmpty { beatStrip }
            if !fallen.isEmpty { fallenLine }
            Button(action: onClose) {
                Text(cs ? "Zavřít" : "Close")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundStyle(tint)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .padding(16)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(tint.opacity(0.5), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 20, y: 8)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: battle.repelled ? "shield.lefthalf.filled" : "flame.fill")
                .font(.caption).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text((cs ? "Bitva" : "Battle").uppercased())
                    .font(.caption2.weight(.bold)).tracking(1.2)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(.title3, design: .serif).weight(.semibold))
                    .foregroundStyle(Theme.text)
            }
            Spacer()
            outcomeBadge
        }
    }

    /// Who came for whom.
    private var engagementLine: some View {
        HStack(spacing: 6) {
            Text(battle.attacker(AppStrings.language))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.text)
            Image(systemName: "arrow.right").font(.caption2).foregroundStyle(Theme.textDim)
            Text(battle.defenderName)
                .font(.subheadline)
                .foregroundStyle(Theme.textDim)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The arc of the fight, beat by beat — the shape the canvas drew, as chips.
    private var beatStrip: some View {
        FlowRow(spacing: 6) {
            ForEach(beats, id: \.self) { beat in
                Label(beatLabel(beat), systemImage: beatIcon(beat))
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(Theme.surfaceInset, in: Capsule())
                    .foregroundStyle(beatTint(beat))
            }
        }
    }

    /// The dead, by name — the part of a battle that must not scroll past.
    private var fallenLine: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "leaf.fill").font(.caption2).foregroundStyle(Theme.danger)
            Text((cs ? "Padli: " : "Fell: ") + fallen.joined(separator: ", "))
                .font(.caption).foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var outcomeBadge: some View {
        Text(battle.repelled ? (cs ? "Odraženo" : "Repelled")
                             : (cs ? "Prolomeno" : "Overrun"))
            .font(.caption2.weight(.bold))
            .padding(.vertical, 3).padding(.horizontal, 8)
            .background(tint.opacity(0.16), in: Capsule())
            .foregroundStyle(tint)
    }

    // MARK: - Derived

    private var tint: Color { battle.repelled ? Theme.good : Theme.danger }

    private var title: String {
        if battle.repelled { return cs ? "Nájezd odražen" : "Raid repelled" }
        if battle.deaths > 0 { return cs ? "Obrana prolomena" : "Defenses broken" }
        return cs ? "Sýpka vyloupena" : "Stores plundered"
    }

    private var fallen: [String] {
        battle.moments.filter { $0.kind == .death }.compactMap(\.pawnName)
    }

    /// The distinct beats that happened, in the order a battle runs.
    private var beats: [BattleMoment.Kind] {
        let present = Set(battle.moments.map(\.kind))
        let order: [BattleMoment.Kind] = [.volley, .charge, .clash, .wound, .death, .plunder, .repelled]
        return order.filter { present.contains($0) }
    }

    private func beatLabel(_ kind: BattleMoment.Kind) -> String {
        switch kind {
        case .volley:   return cs ? "Salva z hradby" : "Volley"
        case .charge:   return cs ? "Útok na palisádu" : "Charge"
        case .clash:    return cs ? "Střet u zdi" : "Clash"
        case .wound:    return "\(battle.wounded) " + (cs ? "raněných" : "wounded")
        case .death:    return "\(battle.deaths) " + (cs ? "padlých" : "fell")
        case .plunder:  return (cs ? "kořist " : "plunder ") + "\(Int(battle.plunder))"
        case .repelled: return cs ? "odraženo" : "held"
        }
    }

    private func beatIcon(_ kind: BattleMoment.Kind) -> String {
        switch kind {
        case .volley:   return "arrow.up.forward"
        case .charge:   return "figure.run"
        case .clash:    return "bolt.fill"
        case .wound:    return "cross.case.fill"
        case .death:    return "xmark"
        case .plunder:  return "shippingbox.fill"
        case .repelled: return "shield.fill"
        }
    }

    private func beatTint(_ kind: BattleMoment.Kind) -> Color {
        switch kind {
        case .death, .plunder: return Theme.danger
        case .repelled:        return Theme.good
        default:               return Theme.textDim
        }
    }
}
