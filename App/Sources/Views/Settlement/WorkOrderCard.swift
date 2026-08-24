import SwiftUI
import EndlessFrontierCore

/// **The card that turns a tap into an order.**
///
/// Keks: *"vše drawn je there, ale pak na věci nejde klikat, vybírat je k akci
/// — max doufat, že se někdy něco stane a někdo k nim půjde."*
///
/// Tapping a tree, a seam of rock or a heap of timber used to raise a capsule
/// with its name in it and nothing else. This is the same capsule with the one
/// thing a player actually wants: *that one, next.*
///
/// It does not order a person anywhere — see `Designation`. It marks the
/// thing, and the trade that was already choosing targets takes the marked one
/// first. So the card promises exactly what the simulation delivers: a
/// woodcutter will get to it, not that somebody is walking there now.
struct WorkOrderCard: View {
    let label: String
    /// What the thing **is**, in the content's own words — one line out of
    /// `flora.json` or `animals.json`. Optional because a heap of timber is a
    /// heap of timber and there is nothing to say about it.
    var detail: String? = nil
    let kind: Designation.Kind
    let marked: Bool
    /// How many colonists hold the trade that would do it. Nobody in the trade
    /// is the honest reason a mark sits there for a season, and saying so is
    /// better than letting the player think the game ignored them.
    let hands: Int
    let onOrder: () -> Void
    let onClose: () -> Void

    private var cs: Bool { AppStrings.language == .cs }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: marked ? "checkmark.circle.fill" : "mappin.circle.fill")
                    .font(.callout)
                    .foregroundStyle(marked ? Theme.good : Theme.accent)
                Text(label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(Theme.textDim)
                }
                .buttonStyle(.plain)
            }
            // What it is, before what you may do to it. A tapped oak should say
            // it is an oak and what an oak is, not only "fell it".
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if marked {
                Text(kind.standing.resolve(AppStrings.language))
                    .font(.caption)
                    .foregroundStyle(Theme.good)
            } else if hands == 0 {
                Text(idleTrade)
                    .font(.caption)
                    .foregroundStyle(Theme.danger)
            }
            Button(action: onOrder) {
                Label(marked ? AppStrings.liftTheOrder
                             : kind.label.resolve(AppStrings.language),
                      systemImage: marked ? "arrow.uturn.backward" : symbol)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .background(marked ? Theme.surfaceInset : Theme.accent.opacity(0.22),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .foregroundStyle(marked ? Theme.textDim : Theme.accent)
        }
        .padding(12)
        .frame(maxWidth: 340)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var symbol: String {
        switch kind {
        case .fell: return "tree.fill"
        case .mine: return "hammer.fill"
        case .haul: return "shippingbox.fill"
        case .hunt: return "scope"
        }
    }

    /// Said plainly, because a mark nobody in the colony can act on is the one
    /// case where the player is owed an explanation rather than patience.
    private var idleTrade: String {
        switch kind {
        case .fell: return cs ? "Nikdo teď nekácí" : "Nobody is cutting wood"
        case .mine: return cs ? "Nikdo teď netěží" : "Nobody is at the rock"
        case .haul: return cs ? "Nikdo teď nenosí" : "Nobody is hauling"
        case .hunt: return cs ? "Nikdo teď neloví" : "Nobody is hunting"
        }
    }
}
