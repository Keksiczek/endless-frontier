import SwiftUI
import EndlessFrontierCore

/// A tap-to-inspect card for a single colonist.
///
/// It used to say health, mood and four inherited numbers, which told you what
/// a colonist *was* and nothing about how they were getting on. A colony sim is
/// about people having a bad time in interesting ways — so this now leads with
/// the four needs, says plainly **why** their mood is where it is, and names
/// the two things that had never been on screen at all: the bed they sleep in
/// and the piece of work they are on.
struct PawnInspectorCard: View {
    /// One bond, resolved to a living name for display.
    struct BondLine: Identifiable {
        let id: UUID
        let name: String
        let kind: RelationKind
    }

    let pawn: Pawn
    let ticksPerYear: Int
    var activity: String?
    var bonds: [BondLine] = []
    /// Why their mood is what it is, from `MoodLedger`.
    var moodFactors: [MoodFactor] = []
    /// Whether the engine has given them a roof.
    var housed: Bool = true
    var onClose: () -> Void

    private var cs: Bool { AppStrings.language == .cs }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            HStack(spacing: 10) {
                vital(icon: "heart.fill", label: "HP", value: pawn.health, tint: Theme.good)
                vital(icon: "face.smiling", label: cs ? "Nálada" : "Mood",
                      value: pawn.mood, tint: Theme.accent)
                if pawn.wealth > 0 {
                    vital(icon: "circle.hexagongrid.fill",
                          label: cs ? "Jmění" : "Wealth",
                          value: nil, text: "\(Int(pawn.wealth))", tint: Theme.textDim)
                }
            }
            needs
            if !moodFactors.isEmpty { moodBreakdown }
            if !bonds.isEmpty { bondRows }
            genes
        }
        .padding(16)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Theme.roleShade(pawn.assignedWork).opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 18, y: 8)
    }

    /// The four needs, with the ones that are biting marked.
    private var needs: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(cs ? "Potřeby" : "Needs")
            NeedBar(label: cs ? "Hlad" : "Food", value: pawn.needs.hunger,
                    icon: "fork.knife", tint: Color(red: 0.85, green: 0.72, blue: 0.42))
            NeedBar(label: cs ? "Spánek" : "Rest", value: pawn.needs.rest,
                    icon: "moon.fill", tint: Color(red: 0.62, green: 0.70, blue: 0.88))
            NeedBar(label: cs ? "Teplo" : "Warmth", value: pawn.needs.warmth,
                    icon: "flame.fill", tint: Color(red: 0.88, green: 0.55, blue: 0.36))
            NeedBar(label: cs ? "Odpočinek" : "Leisure", value: pawn.needs.recreation,
                    icon: "leaf.fill", tint: Color(red: 0.60, green: 0.80, blue: 0.62))
            if !housed {
                HStack(spacing: 5) {
                    Image(systemName: "house.slash").font(.caption2)
                    Text(cs ? "Nemá kde spát" : "Nowhere to sleep")
                        .font(.caption)
                }
                .foregroundStyle(Theme.danger)
            }
        }
    }

    /// Why they feel the way they do — the thing a mood number can never say.
    private var moodBreakdown: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionTitle(cs ? "Proč" : "Why")
            ForEach(moodFactors.prefix(5)) { factor in
                HStack(spacing: 6) {
                    Text(factor.label.resolve(AppStrings.language))
                        .font(.caption)
                        .foregroundStyle(Theme.text)
                    Spacer(minLength: 8)
                    Text(factor.amount >= 0
                         ? "+\(Int(factor.amount.rounded()))"
                         : "\(Int(factor.amount.rounded()))")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(factor.amount >= 0 ? Theme.good : Theme.danger)
                }
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.bold)).tracking(1.2)
            .foregroundStyle(Theme.textDim)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(pawn.name)
                    .font(.system(.title3, design: .serif).weight(.semibold))
                    .foregroundStyle(Theme.text)
                HStack(spacing: 6) {
                    Circle().fill(Theme.roleShade(pawn.assignedWork)).frame(width: 7, height: 7)
                    Text(AppStrings.roleName(pawn.assignedWork))
                        .foregroundStyle(Theme.textDim)
                    Text("· \(pawn.ageYears(ticksPerYear: ticksPerYear)) \(AppStrings.language == .cs ? "let" : "yrs")")
                        .foregroundStyle(Theme.textDim)
                }
                .font(.caption)
                // What they're visibly doing on the canvas this moment.
                if let activity {
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill").font(.system(size: 8))
                        Text(activity)
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.accent.opacity(0.9))
                }
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.textDim)
            }
            .accessibilityLabel("Close")
        }
    }

    /// Who this colonist's life is entangled with.
    private var bondRows: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(AppStrings.language == .cs ? "Vztahy" : "Bonds")
                .font(.caption2.weight(.bold)).tracking(1.2)
                .foregroundStyle(Theme.textDim)
            ForEach(bonds) { bond in
                HStack(spacing: 6) {
                    Image(systemName: bondIcon(bond.kind))
                        .font(.caption2)
                        .foregroundStyle(bondTint(bond.kind))
                        .frame(width: 14)
                    Text(bond.name)
                        .font(.caption)
                        .foregroundStyle(Theme.text)
                    Text(bondLabel(bond.kind))
                        .font(.caption2)
                        .foregroundStyle(Theme.textDim)
                }
            }
        }
    }

    private func bondIcon(_ kind: RelationKind) -> String {
        switch kind {
        case .partner: return "heart.fill"
        case .friend: return "person.2.fill"
        case .rival: return "bolt.fill"
        }
    }

    private func bondTint(_ kind: RelationKind) -> Color {
        switch kind {
        case .partner: return Theme.danger.opacity(0.85)
        case .friend: return Theme.good
        case .rival: return Theme.accent
        }
    }

    private func bondLabel(_ kind: RelationKind) -> String {
        let cs = AppStrings.language == .cs
        switch kind {
        case .partner: return cs ? "manžel(ka)" : "spouse"
        case .friend: return cs ? "přítel" : "friend"
        case .rival: return cs ? "sok" : "rival"
        }
    }

    private func vital(icon: String, label: String, value: Double?, text: String? = nil, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.caption2).foregroundStyle(Theme.textDim)
                Text(text ?? "\(Int((value ?? 0).rounded()))")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Theme.text)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(Theme.surfaceInset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var genes: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(AppStrings.language == .cs ? "Vlohy" : "Disposition")
                .font(.caption2.weight(.bold)).tracking(1.2)
                .foregroundStyle(Theme.textDim)
            GeneBar(label: AppStrings.language == .cs ? "Píle" : "Industry", value: pawn.genes.industry)
            GeneBar(label: AppStrings.language == .cs ? "Plodnost" : "Fertility", value: pawn.genes.fertility)
            GeneBar(label: AppStrings.language == .cs ? "Družnost" : "Sociability", value: pawn.genes.sociability)
            GeneBar(label: AppStrings.language == .cs ? "Odvaha" : "Courage", value: pawn.genes.courage)
        }
    }
}

/// A need, 0…100, with the colour warning you when it is running out.
private struct NeedBar: View {
    let label: String
    let value: Double
    let icon: String
    let tint: Color

    /// A need under this is doing them harm, and is drawn as such — the point
    /// of a bar is that you can see trouble without reading the number.
    private var urgent: Bool { value < 30 }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(urgent ? Theme.danger : tint)
                .frame(width: 12)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.textDim)
                .frame(width: 62, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.surfaceInset)
                    Capsule()
                        .fill(urgent ? Theme.danger : tint)
                        .frame(width: geo.size.width * CGFloat(min(max(value / 100, 0), 1)))
                }
            }
            .frame(height: 5)
            Text("\(Int(value.rounded()))")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(urgent ? Theme.danger : Theme.textDim)
                .frame(width: 26, alignment: .trailing)
        }
    }
}

/// A slim 0…1 disposition bar.
private struct GeneBar: View {
    let label: String
    let value: Double

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.textDim)
                .frame(width: 78, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.surfaceInset)
                    Capsule().fill(Theme.bone.opacity(0.7))
                        .frame(width: geo.size.width * CGFloat(min(max(value, 0), 1)))
                }
            }
            .frame(height: 4)
            Text(String(format: "%.2f", value))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Theme.textDim)
                .frame(width: 34, alignment: .trailing)
        }
    }
}
