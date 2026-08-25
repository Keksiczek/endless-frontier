import SwiftUI
import EndlessFrontierCore

/// The settlement's living diary: births and roofs, chats and quarrels,
/// weddings and grief — newest first, each stamped with its in-game year.
/// The simulation always did these things; now they're on the record.
struct JournalPanel: View {
    @Bindable var game: GameViewModel

    /// How much history the panel shows before it stops scrolling the past.
    private let visibleEntries = 40

    private var cs: Bool { AppStrings.language == .cs }

    private var entries: [ColonyLogEntry] {
        Array((game.selectedSettlement?.journal.entries ?? []).suffix(visibleEntries).reversed())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: cs ? "Deník osady" : "Colony journal")
            if entries.isEmpty {
                Text(cs
                     ? "Zatím ticho — deník se začne plnit, jak osada žije."
                     : "Quiet so far — the diary fills as the settlement lives.")
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

/// What the colony is raising right now: each open site with its progress —
/// and who's on the tools. Construction takes time now; this is where you
/// watch it happen (besides the scaffolding on the canvas itself).
struct ConstructionPanel: View {
    @Bindable var game: GameViewModel

    private var cs: Bool { AppStrings.language == .cs }

    private var projects: [ConstructionProject] {
        game.selectedSettlement?.constructions ?? []
    }

    private var builderCount: Int {
        game.selectedSettlement?.pawns.filter { $0.assignedWork == .building }.count ?? 0
    }

    var body: some View {
        if !projects.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionHeader(title: cs ? "Ve výstavbě" : "Under construction")
                    Spacer()
                    Label("\(builderCount)", systemImage: "hammer.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textDim)
                        .accessibilityLabel(cs ? "\(builderCount) stavitelů" : "\(builderCount) builders")
                }
                ForEach(projects) { project in
                    row(project)
                }
            }
            .frontierCard()
        }
    }

    private func row(_ project: ConstructionProject) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(game.buildingName(project.definitionID))
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(Int(project.fraction * 100)) %")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.textDim)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.surfaceInset)
                    Capsule().fill(Theme.accent.opacity(0.85))
                        .frame(width: geo.size.width * CGFloat(project.fraction))
                }
            }
            .frame(height: 5)
        }
        .padding(.vertical, 2)
    }
}
