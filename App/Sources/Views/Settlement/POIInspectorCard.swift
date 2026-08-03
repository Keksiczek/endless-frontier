import SwiftUI
import EndlessFrontierCore

/// A landmark the scouts found: what the place is, what it has left to give,
/// and the button that sends people out to it.
///
/// Points of interest used to end at the moment of discovery — a name in a
/// capsule and nothing you could do about it. Then they had a button that paid
/// instantly, which is not much better: nobody went anywhere. Now the card is a
/// window on a journey. Press it and named colonists leave; while they are out
/// the card says who went and how far along they are; the haul lands in the
/// journal when they walk back in.
struct POIInspectorCard: View {
    let poi: LocalPOI
    let ticksPerYear: Int
    let tick: Int
    /// Both clocks at once — what the journey is measured against.
    private var clock: WorldClock { WorldClock(tick: tick, step: 0) }
    /// The party out at this place, if one is.
    var expedition: POIExpedition?
    /// Who went, by name.
    var partyNames: [String] = []
    /// Whether the colony can actually field a party right now.
    var canDispatch: Bool
    var onDispatch: () -> Void
    var onClose: () -> Void

    private var cs: Bool { AppStrings.language == .cs }

    private var isReady: Bool { poi.isWorkable(tick: tick, ticksPerYear: ticksPerYear) }

    private var yearsUntilReady: Int {
        let ticks = poi.ticksUntilReady(tick: tick, ticksPerYear: ticksPerYear)
        return Int((Double(ticks) / Double(max(1, ticksPerYear))).rounded(.up))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let expedition {
                journey(expedition)
            } else {
                Text(flavor)
                    .font(.caption)
                    .foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
                cost
                actionRow
            }
        }
        .padding(16)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 18, y: 8)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(poi.kind.displayLabel)
                    .font(.system(.title3, design: .serif).weight(.semibold))
                    .foregroundStyle(Theme.text)
                Text(statusLine)
                    .font(.caption)
                    .foregroundStyle(poi.isExhausted ? Theme.textDim : Theme.accent)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.textDim)
            }
            .accessibilityLabel(cs ? "Zavřít" : "Close")
        }
    }

    // MARK: - A party that is out

    /// What the party is doing right now, and how much of the journey is left.
    private func journey(_ expedition: POIExpedition) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: phaseIcon(expedition))
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
                Text(phaseLine(expedition))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.text)
            }
            ProgressView(value: overallProgress(expedition))
                .tint(Theme.accent)
            if !partyNames.isEmpty {
                Text(partyNames.joined(separator: ", "))
                    .font(.caption2)
                    .foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let site = expedition.site { insideThePlace(site) }
            Text(cs
                 ? "Zatím nepracují v osadě — jejich ruce chybí."
                 : "They are not working the colony while they are gone.")
                .font(.caption2)
                .foregroundStyle(Theme.textDim)
        }
    }

    /// What is in there, and what has happened to them so far.
    ///
    /// The one thing a visit never used to have: a *middle*. The party walked
    /// out, a number was rolled somewhere off screen, and they walked back —
    /// so there was nothing to look at and nothing to worry about. These are
    /// the beats the simulation is writing as they happen.
    @ViewBuilder
    private func insideThePlace(_ site: SiteEncounter) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                tally("shippingbox.fill",
                      site.things.count { $0.kind == .cache && !$0.done },
                      Theme.accent)
                tally("hare.fill", site.things.count { $0.kind == .guardian && !$0.done },
                      Theme.danger)
                tally("exclamationmark.triangle.fill",
                      site.things.count { $0.kind == .trap && !$0.done }, Theme.textDim)
                Spacer()
                Text("\(Int(site.progress * 100)) %")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Theme.textDim)
            }
            ForEach(site.beats.suffix(3)) { beat in
                Text(line(for: beat))
                    .font(.caption2)
                    .foregroundStyle(Theme.text.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private func tally(_ symbol: String, _ count: Int, _ tint: Color) -> some View {
        if count > 0 {
            Label("\(count)", systemImage: symbol)
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(tint)
        }
    }

    private func line(for beat: SiteEncounter.Beat) -> String {
        let who = beat.pawnName ?? (cs ? "Výprava" : "The party")
        let what = beat.thingLabel?.resolve(AppStrings.language) ?? ""
        switch beat.kind {
        case .arrived:
            return cs ? "Došli na místo — \(Int(beat.amount)) věcí k prohledání."
                      : "They are there — \(Int(beat.amount)) things to deal with."
        case .opened:  return cs ? "\(who) otevřel(a): \(what)." : "\(who) got into \(what)."
        case .sprung:
            guard beat.amount > 0 else {
                return cs ? "\(who) si všiml(a) včas: \(what)." : "\(who) spotted \(what) in time."
            }
            return cs ? "\(what) — a \(who) do toho spadl(a)."
                      : "\(what), and \(who) went into it."
        case .fought:  return cs ? "\(who) se pere s tím, co tam je." : "\(who) is fighting \(what)."
        case .killed:  return cs ? "\(who) to dostal(a): \(what)." : "\(who) put down \(what)."
        case .driven:  return cs ? "Vyhnali je ven." : "They were driven out."
        case .cleared: return cs ? "Místo je prohledané." : "The place is picked clean."
        case .left:
            return cs ? "Odešli — \(Int(beat.amount)) nechali být."
                      : "They left \(Int(beat.amount)) behind."
        }
    }

    /// Progress across the whole trip, not just the current leg — a bar that
    /// resets twice would read as going backwards.
    private func overallProgress(_ expedition: POIExpedition) -> Double {
        expedition.journeyProgress(at: clock)
    }

    private func phaseIcon(_ expedition: POIExpedition) -> String {
        switch expedition.phase(at: clock) {
        case .outbound: return "figure.walk.motion"
        case .working: return "hammer.fill"
        case .returning: return "arrow.uturn.left"
        case nil: return "checkmark.circle.fill"
        }
    }

    private func phaseLine(_ expedition: POIExpedition) -> String {
        let left = expedition.ticksRemaining(at: clock)
        let back = cs ? "zpět za \(left) t." : "back in \(left) ticks"
        switch expedition.phase(at: clock) {
        case .outbound: return cs ? "Na cestě tam — \(back)" : "On the way out — \(back)"
        case .working: return cs ? "Pracují na místě — \(back)" : "Working the site — \(back)"
        case .returning: return cs ? "Na cestě zpět — \(back)" : "Heading home — \(back)"
        case nil: return cs ? "Právě dorazili" : "Just arrived home"
        }
    }

    // MARK: - Sending one out

    /// What the trip will ask of the colony, before it is ordered.
    private var cost: some View {
        HStack(spacing: 14) {
            Label("\(poi.kind.partySize)", systemImage: "person.2.fill")
            Label(cs ? "\(tripTicks) t." : "\(tripTicks) ticks", systemImage: "clock")
            if poi.kind.hazardChance > 0 {
                Label(cs ? "riziko" : "risky", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.danger)
            }
        }
        .font(.caption2.weight(.semibold).monospacedDigit())
        .foregroundStyle(Theme.textDim)
    }

    /// The round trip in ticks, so the player can weigh the walk before making it.
    private var tripTicks: Int {
        LocalPOIEngine.travelTicks(to: poi.position) * 2 + poi.kind.workTicks
    }

    private var statusLine: String {
        if poi.isExhausted { return cs ? "Vytěženo" : "Picked clean" }
        if !isReady {
            let y = yearsUntilReady
            return cs ? "Odpočívá — ještě \(y) \(y == 1 ? "rok" : y < 5 ? "roky" : "let")"
                      : "Resting — \(y) year\(y == 1 ? "" : "s") to go"
        }
        if poi.kind.isRenewable { return cs ? "Připraveno" : "Ready" }
        let left = poi.kind.maxVisits - poi.visits
        return cs ? "Zbývá výprav: \(left)" : "\(left) run\(left == 1 ? "" : "s") left"
    }

    private var flavor: String {
        switch poi.kind {
        case .ruins: return cs
            ? "Kámen po kameni se dá ze zřícenin vytěžit staré vědění."
            : "Worked stone by stone, the ruins give up what the ages left."
        case .cave: return cs
            ? "Kámen je tam v hojnosti — a strop nedrží vždycky."
            : "Stone in plenty down there — and the roof does not always hold."
        case .spring: return cs
            ? "Osada k němu může dojít, kdykoli je potřeba. Pramen nevyschne, jen chce čas."
            : "The colony can walk out whenever it needs to. A spring does not run dry — it only needs time."
        case .treasure: return cs
            ? "Skrýš vydá všechno naráz. Kdo ji zakopal, už jí neželí."
            : "The cache gives up everything at once. Whoever buried it is past minding."
        case .shrine: return cs
            ? "Noc u starého oltáře vrací lidem klid — a víře sílu."
            : "A night at the old altar settles people — and steadies the faith."
        case .wreck: return cs
            ? "Dřevo, kování a co zbylo pod plachtou."
            : "Timber, ironwork, and whatever is still under the canvas."
        case .orchard: return cs
            ? "Něčí sad, hodně dávno. Přestali chodit — sad rodit nepřestal."
            : "Somebody's orchard, a long time ago. They stopped coming; it did not stop bearing."
        case .hermit: return cs
            ? "Nedá nic na prahu. Sedněte si — a vrátí se vám lepší ve svém řemesle."
            : "He gives nothing on the doorstep. Sit down, and they come home better at their trades."
        case .watchtower: return cs
            ? "Čtyři sta let staré schodiště. Z jeho hlavy se kraj obkreslí sám."
            : "Four hundred years of stair. From its head the country draws itself."
        case .saltPan: return cs
            ? "Sůl je rozdíl mezi masem a masem, které vydrží do jara."
            : "Salt is the difference between meat and meat that keeps until spring."
        case .barrow: return cs
            ? "Pohřbili ho bohatě. Vzít si to jde jednou — a osada to nese těžce."
            : "They buried them rich. You can take it once, and the colony will feel it."
        case .starfall: return cs
            ? "Není to kámen. Za tu cestu to stojí — a bezpečné to není."
            : "It is not stone. Worth every day of the walk, and not safe."
        }
    }

    private var actionRow: some View {
        Button(action: onDispatch) {
            Label(actionLabel, systemImage: actionIcon)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(poi.kind.hazardChance > 0 ? Theme.danger : Theme.accent)
        .disabled(!canDispatch)
        .accessibilityHint(canDispatch ? "" : blockedReason)
    }

    /// A disabled button that does not say why is a bug report waiting to
    /// happen. Say which of the three reasons it is.
    private var blockedReason: String {
        if poi.isExhausted { return cs ? "Už tu nic není" : "Nothing left here" }
        if !isReady { return statusLine }
        return cs ? "Není koho poslat" : "Nobody to spare"
    }

    private var actionLabel: String {
        guard canDispatch else { return blockedReason }
        switch poi.kind {
        case .ruins: return cs ? "Poslat učence" : "Send scholars"
        case .cave: return cs ? "Poslat lamače" : "Send a cutting crew"
        case .spring: return cs ? "Poslat pro vodu" : "Send for water"
        case .treasure: return cs ? "Poslat vykopat skrýš" : "Send to dig it out"
        case .shrine: return cs ? "Vyslat poutníky" : "Send pilgrims"
        case .wreck: return cs ? "Poslat rozebrat vrak" : "Send a salvage party"
        case .orchard: return cs ? "Poslat česáče" : "Send pickers"
        case .hermit: return cs ? "Poslat se učit" : "Send them to learn"
        case .watchtower: return cs ? "Poslat na věž" : "Send them up the tower"
        case .saltPan: return cs ? "Poslat hrabat sůl" : "Send salt rakers"
        case .barrow: return cs ? "Otevřít mohylu" : "Open the mound"
        case .starfall: return cs ? "Poslat vysekat hvězdu" : "Send to cut the star out"
        }
    }

    private var actionIcon: String {
        guard canDispatch else { return poi.isExhausted ? "circle.slash" : "hourglass" }
        return poi.kind.hazardChance > 0 ? "exclamationmark.triangle.fill" : "figure.walk"
    }
}
