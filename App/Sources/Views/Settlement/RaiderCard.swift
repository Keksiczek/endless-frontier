import SwiftUI
import EndlessFrontierCore

/// **The people who came to take the place.**
///
/// Keks: *"nejde vybrat raidery."* Every other body on the field answered a
/// tap — colonists, beasts, prisoners, even a heap of timber — and the one
/// kind of person the player is actually fighting answered nothing. So a raid
/// was a wave of identical silhouettes: no way to ask which of them was
/// carrying what, which one was walking at your granary, or how much of one
/// was left.
///
/// Everything here is read off `Siege.Combatant`, which the simulation has
/// been keeping all along: what they came for (`intent`), who they have closed
/// on, what is left of them, and — through `Siege.era` and the camp that sent
/// them — what they are carrying.
///
/// Tapping a raider while one of your own is selected still gives an **order**
/// rather than opening this (`SettlementCanvasView.siegeOrder`); the card is
/// what a tap means when nobody is picked out of the line.
struct RaiderCard: View {
    let raider: Siege.Combatant
    let siege: Siege
    /// What the warband is called, already resolved into the player's language.
    let band: String
    var onClose: () -> Void

    private var cs: Bool { AppStrings.language == .cs }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            HStack(spacing: 10) {
                vital(icon: "figure.walk", label: cs ? "Záměr" : "Intent", text: intent)
                vital(icon: "shield.lefthalf.filled", label: cs ? "Síla" : "Strength",
                      text: strength)
                vital(icon: armsIcon, label: cs ? "Zbraň" : "Arms", text: arms)
            }
            Text(doing)
                .font(.caption)
                .foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: 360)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Theme.danger.opacity(0.45), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 18, y: 8)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                // **Their name, when they have one.** A warband was a set of
                // interchangeable tokens; the card led with the band because
                // there was nothing else to lead with. A raid you can name is
                // a raid you remember. Older saves have no names and fall back
                // to the band exactly as before.
                Text(raider.name ?? band)
                    .font(.system(.title3, design: .serif).weight(.semibold))
                    .foregroundStyle(Theme.text)
                Text(raider.name == nil
                     ? (cs ? "na tvé půdě" : "on your ground")
                     : (cs ? "\(band) — na tvé půdě" : "\(band) — on your ground"))
                    .font(.caption)
                    .foregroundStyle(Theme.textDim)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.textDim)
            }
            .buttonStyle(.plain)
        }
    }

    private func vital(icon: String, label: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption2).foregroundStyle(Theme.textDim)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.caption2).foregroundStyle(Theme.textDim)
                Text(text).font(.caption.weight(.semibold)).foregroundStyle(Theme.text)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// What this one came for. The warband musters with three purposes in it,
    /// and which one a given figure is carrying is why it is walking where it
    /// is walking.
    private var intent: String {
        switch raider.intent {
        case .fight: return cs ? "bít se" : "to fight"
        case .plunder: return cs ? "pro zásoby" : "for the stores"
        case .burn: return cs ? "zapálit" : "to burn"
        }
    }

    /// What is left of them, as a word. A colony counts bodies, not decimals.
    private var strength: String {
        let share = raider.strength / max(1, siege.openingStrength / Double(max(1, siege.attackers)))
        switch share {
        case ..<0.25: return cs ? "na nohou taktak" : "barely standing"
        case ..<0.6: return cs ? "pochroumaný" : "cut up"
        case ..<0.95: return cs ? "škrábnutý" : "scratched"
        default: return cs ? "nedotčený" : "untouched"
        }
    }

    /// A warband carries the arms of the age it fights in — and a camp of
    /// deserters carries the arms of a later one (`OutlawCamp.armsEra`).
    private var arms: String {
        switch siege.era {
        case .earlySettlement: return cs ? "kameny" : "stones"
        case .ancient: return cs ? "luky" : "bows"
        case .medieval: return cs ? "kuše" : "crossbows"
        case .earlyIndustrial: return cs ? "muškety" : "muskets"
        case .modern: return cs ? "pušky" : "rifles"
        case .nearFuture: return cs ? "paprskomety" : "beam arms"
        }
    }

    private var armsIcon: String {
        switch siege.era {
        case .earlySettlement, .ancient, .medieval: return "arrow.up.forward"
        default: return "scope"
        }
    }

    /// Where they are in the fight, said plainly.
    private var doing: String {
        if raider.down { return cs ? "Leží." : "Down." }
        if raider.target != nil {
            return cs ? "Je v kontaktu s někým z tvých."
                      : "In contact with one of yours."
        }
        switch raider.intent {
        case .plunder:
            return cs ? "Míří k zásobám a obejde každého, kdo mu nestojí v cestě."
                      : "Making for the stores, and going round anybody not in the way."
        case .burn:
            return cs ? "Vybral si jednu střechu a jde si pro ni."
                      : "Picked one roof before they set off, and is walking at it."
        case .fight:
            return cs ? "Hledá, s kým se srazit." : "Looking for somebody to close with."
        }
    }
}
