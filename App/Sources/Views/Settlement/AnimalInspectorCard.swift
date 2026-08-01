import SwiftUI
import EndlessFrontierCore

/// A tap-to-inspect card for one beast.
///
/// The wild became pawns — a body part by part, wounds, illness, cold, a small
/// mind with something it is doing — and it was the only living thing on the
/// map you could not ask about. A deer was a shape that moved. This is the
/// colonist card's question asked of an animal: what is it, how is it, what is
/// it doing, and how far anybody has got with gentling it.
struct AnimalInspectorCard: View {
    let animal: Animal
    /// Set when this beast belongs to the colony rather than to the valley.
    var kept: TamedAnimal?
    var onClose: () -> Void

    private var cs: Bool { AppStrings.language == .cs }
    private var vigour: Double { animal.health / max(1, animal.species.baseHealth) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            HStack(spacing: 10) {
                vital(icon: "heart.fill", label: cs ? "Zdraví" : "Health",
                      text: "\(Int(animal.health))/\(Int(animal.species.baseHealth))",
                      tint: vigour < 0.4 ? Theme.danger : Theme.good)
                vital(icon: animal.species.isPredator ? "pawprint.fill" : "leaf.fill",
                      label: cs ? "Věk" : "Age",
                      text: "\(animal.age / 60) \(cs ? "let" : "yrs")",
                      tint: Theme.textDim)
            }
            if !animal.conditions.isEmpty { conditions }
            if kept == nil, animal.tameProgress > 0.01 { taming }
            body_
        }
        .padding(16)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Theme.accent.opacity(kept != nil ? 0.45 : 0.20), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 18, y: 8)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(kept?.name ?? animal.species.displayName.resolve(AppStrings.language))
                    .font(.system(.title3, design: .serif).weight(.semibold))
                    .foregroundStyle(Theme.text)
                HStack(spacing: 6) {
                    if let kept {
                        Circle().fill(Theme.accent).frame(width: 7, height: 7)
                        Text(kept.role.displayName.resolve(AppStrings.language))
                    } else {
                        Circle().fill(Theme.boneDim).frame(width: 7, height: 7)
                        Text(cs ? "divoké" : "wild")
                    }
                    Text("· \(doing)")
                }
                .font(.caption)
                .foregroundStyle(Theme.textDim)
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

    /// What it is up to, in words — the small mind made legible.
    private var doing: String {
        if kept != nil { return cs ? "u osady" : "about the yard" }
        switch animal.activity {
        case .grazing: return cs ? "pase se" : "grazing"
        case .wary: return cs ? "ostražité" : "wary"
        case .fleeing: return cs ? "prchá" : "fleeing"
        case .stalking: return cs ? "loví" : "stalking"
        case .resting: return cs ? "leží" : "lying up"
        }
    }

    /// What it is carrying — the same question the colonist card asks.
    private var conditions: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionTitle(cs ? "Neduhy" : "Ailments")
            ForEach(animal.conditions) { condition in
                HStack(spacing: 6) {
                    Image(systemName: icon(condition.kind))
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.danger)
                        .frame(width: 12)
                    Text(condition.label.resolve(AppStrings.language))
                        .font(.caption)
                        .foregroundStyle(Theme.text)
                    Spacer(minLength: 6)
                    Text("\(Int(condition.severity * 100)) %")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Theme.textDim)
                }
            }
        }
    }

    private func icon(_ kind: AnimalConditionKind) -> String {
        switch kind {
        case .injury: return "drop.fill"
        case .disease: return "allergens"
        case .frostbite: return "snowflake"
        case .heatstroke: return "sun.max.fill"
        }
    }

    /// How far somebody has got with it — the thing you actually want to know
    /// about a wild beast a hunter has been visiting.
    private var taming: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionTitle(cs ? "Ochočování" : "Taming")
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.surfaceInset)
                    Capsule().fill(Theme.accent)
                        .frame(width: geo.size.width * CGFloat(min(1, animal.tameProgress)))
                }
            }
            .frame(height: 5)
            Text(cs ? "\(Int(animal.tameProgress * 100)) % — pak zůstane"
                    : "\(Int(animal.tameProgress * 100))% — then it stays")
                .font(.caption2)
                .foregroundStyle(Theme.textDim)
        }
    }

    /// The body, part by part — the reason an animal is a pawn and not a sprite.
    private var body_: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionTitle(cs ? "Tělo" : "Body")
            let broken = animal.body.filter { $0.missing || $0.condition < 0.99 }
            if broken.isEmpty {
                Text(cs ? "Celé a zdravé." : "Whole and sound.")
                    .font(.caption).foregroundStyle(Theme.textDim)
            } else {
                ForEach(broken, id: \.kind) { part in
                    HStack(spacing: 6) {
                        Text(partName(part.kind))
                            .font(.caption).foregroundStyle(Theme.text)
                        Spacer(minLength: 6)
                        Text(part.missing
                             ? (cs ? "chybí" : "gone")
                             : "\(Int(part.condition * 100)) %")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(part.missing ? Theme.danger : Theme.textDim)
                    }
                }
            }
            if !animal.canWalk {
                Text(cs ? "Nemůže chodit." : "Cannot walk.")
                    .font(.caption).foregroundStyle(Theme.danger)
            }
        }
    }

    private func partName(_ kind: AnimalBodyPartKind) -> String {
        switch kind {
        case .head: return cs ? "Hlava" : "Head"
        case .torso: return cs ? "Trup" : "Torso"
        case .frontLeftLeg: return cs ? "Levá přední" : "Front left leg"
        case .frontRightLeg: return cs ? "Pravá přední" : "Front right leg"
        case .backLeftLeg: return cs ? "Levá zadní" : "Back left leg"
        case .backRightLeg: return cs ? "Pravá zadní" : "Back right leg"
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.bold)).tracking(1.2)
            .foregroundStyle(Theme.textDim)
    }

    private func vital(icon: String, label: String, text: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.caption2).foregroundStyle(Theme.textDim)
                Text(text)
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Theme.text)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(Theme.surfaceInset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
