import SwiftUI
import EndlessFrontierCore

/// The settlement's living diary: births and roofs, chats and quarrels,
/// weddings and grief — newest first, each stamped with its in-game year.
/// The simulation always did these things; now they're on the record.
struct JournalPanel: View {
    @Bindable var game: GameViewModel

    /// How much history the panel shows before it stops scrolling the past.
    private let visibleEntries = 40

    /// **What the player is looking for, out of everything that happened.**
    ///
    /// Forty lines of a living colony is mostly chatter — friendships, stories
    /// by the well, a roof going on — and a death scrolls past inside a minute.
    /// Keks: *"lidé umřeli na zvěř ale nevím o tom."* They were in the diary the
    /// whole time; there was no way to ask for them.
    private enum Lens: String, CaseIterable, Identifiable {
        case all, deaths, danger, people, work
        var id: String { rawValue }

        func title(_ cs: Bool) -> String {
            switch self {
            case .all:    return cs ? "Vše" : "All"
            case .deaths: return cs ? "Úmrtí" : "Deaths"
            case .danger: return cs ? "Nebezpečí" : "Danger"
            case .people: return cs ? "Lidé" : "People"
            case .work:   return cs ? "Práce" : "Work"
            }
        }

        /// Nil means everything. Grouped the way a player asks the question,
        /// not the way `ColonyLogEntry.Kind` happens to be spelled.
        var kinds: Set<ColonyLogEntry.Kind>? {
            switch self {
            case .all:    return nil
            case .deaths: return [.death]
            case .danger: return [.danger, .death]
            case .people: return [.social, .birth, .arrival, .departure, .faith]
            case .work:   return [.work, .construction, .discovery]
            }
        }
    }
    @State private var lens: Lens = .all

    private var cs: Bool { AppStrings.language == .cs }

    private var entries: [ColonyLogEntry] {
        let all = game.selectedSettlement?.journal.entries ?? []
        // Filtered *before* the tail is taken, or asking for deaths shows the
        // deaths out of the last forty lines rather than the last forty deaths.
        let kept = lens.kinds.map { kinds in all.filter { kinds.contains($0.kind) } } ?? all
        return Array(kept.suffix(visibleEntries).reversed())
    }

    /// How many lines each lens would show, so an empty one reads as "none of
    /// those happened" rather than as a broken filter.
    private func count(_ lens: Lens) -> Int {
        let all = game.selectedSettlement?.journal.entries ?? []
        guard let kinds = lens.kinds else { return all.count }
        return all.count { kinds.contains($0.kind) }
    }

    private var lensPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Lens.allCases) { option in
                    let on = option == lens
                    Button {
                        withAnimation(.snappy(duration: 0.18)) { lens = option }
                    } label: {
                        HStack(spacing: 4) {
                            Text(option.title(cs)).font(.caption2.weight(.semibold))
                            Text("\(count(option))")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(Theme.textDim)
                        }
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(on ? Theme.accent.opacity(0.18) : Theme.surfaceInset,
                                    in: Capsule())
                        .foregroundStyle(on ? Theme.accent : Theme.textDim)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: cs ? "Deník osady" : "Colony journal")
            lensPicker
            if entries.isEmpty {
                Text(lens == .all
                     ? (cs ? "Zatím ticho — deník se začne plnit, jak osada žije."
                           : "Quiet so far — the diary fills as the settlement lives.")
                     : (cs ? "Nic takového se zatím nestalo."
                           : "Nothing of that kind has happened yet."))
                    .font(.caption)
                    .foregroundStyle(Theme.textDim)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(entries) { entry in
                        row(entry)
                        if entry.id != entries.last?.id {
                            Divider().overlay(Theme.boneFaint.opacity(0.25))
                        }
                    }
                }
            }
        }
        .frontierCard()
    }

    private func row(_ entry: ColonyLogEntry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: GameViewModel.icon(for: entry.kind))
                .font(.caption)
                .foregroundStyle(tint(entry.kind))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.text.resolve(AppStrings.language))
                    .font(.caption)
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(cs ? "Rok" : "Year") \(Season.year(tick: entry.tick, ticksPerYear: game.ticksPerYear))")
                    .font(.caption2)
                    .foregroundStyle(Theme.textDim)
            }
            Spacer(minLength: 0)
            // A line that names somebody should take you to them. The toast
            // version of this entry already flies the camera; the written
            // record was a dead end (§11.24).
            if entry.subject != nil {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(Theme.textDim.opacity(0.6))
            }
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onTapGesture {
            guard let subject = entry.subject else { return }
            game.lookAt(subject)
            if case .pawn(let id) = subject { game.focus(pawn: id) }
        }
    }

    private func tint(_ kind: ColonyLogEntry.Kind) -> Color {
        switch kind {
        case .danger, .death: return Theme.danger
        case .birth: return Theme.good
        case .social: return Theme.good.opacity(0.85)
        case .discovery: return Theme.accent
        case .construction, .work: return Theme.textDim
        case .arrival, .departure, .faith: return Theme.accent.opacity(0.8)
        // A declaration and a treaty are both the colour of the thing they
        // decide, which is a war.
        case .diplomacy: return Theme.danger.opacity(0.85)
        }
    }
}

// `ConstructionPanel` used to live down here, under the journal it has nothing
// to do with. It is in `ConstructionPanel.swift` now.
