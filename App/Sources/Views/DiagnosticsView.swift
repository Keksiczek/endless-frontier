import SwiftUI
import UIKit
import EndlessFrontierCore

/// A developer/playtest window onto the simulation: fast-forward time to trigger
/// events, watch who is born, arrives, dies or secedes, and copy the log to send
/// as feedback. This is where the "migrants don't add colonists" report gets
/// pinned down — choice-gated events are flagged in the log.
struct DiagnosticsView: View {
    @Bindable var game: GameViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    @State private var copiedReport = false

    private var cs: Bool { AppStrings.language == .cs }
    private var diag: Diagnostics { game.diagnostics }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    blockersCard
                    summaryCard
                    simulateCard
                    reportCard
                    logCard
                }
                .padding(16)
            }
            .background(Theme.surface)
            .navigationTitle(cs ? "Diagnostika" : "Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(cs ? "Hotovo" : "Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        // One tap gets everything worth sending: the state and
                        // its reasons first, then the history that led there.
                        UIPasteboard.general.string = game.worldReport
                            + "\n\n" + String(repeating: "─", count: 32) + "\n"
                            + diag.transcript
                        copied = true
                    } label: {
                        Label(copied ? (cs ? "Zkopírováno" : "Copied")
                                     : (cs ? "Kopírovat" : "Copy"),
                              systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                }
            }
        }
        .foregroundStyle(Theme.text)
    }

    /// What can't happen right now, and the number that proves it. Top of the
    /// screen because "why is nothing happening" is the question a playtest
    /// actually has — a log of what *did* happen can never answer it.
    @ViewBuilder
    private var blockersCard: some View {
        let blockers = game.blockers
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: cs ? "Co teď nemůže nastat" : "Cannot happen right now")
            if blockers.isEmpty {
                Label(cs ? "Nic není zablokované — všechny systémy můžou naskočit."
                         : "Nothing blocked — every system can fire.",
                      systemImage: "checkmark.seal.fill")
                    .font(.caption).foregroundStyle(Theme.good)
            } else {
                ForEach(blockers, id: \.system) { blocker in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "xmark.octagon.fill")
                            .font(.caption2).foregroundStyle(Theme.danger)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(blocker.system)
                                .font(.caption.weight(.semibold)).foregroundStyle(Theme.text)
                            Text(blocker.reason)
                                .font(.caption2).foregroundStyle(Theme.textDim)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .frontierCard()
    }

    /// The full readout, and the thing worth sending.
    private var reportCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: cs ? "Plný report" : "Full report")
                Spacer()
                Button {
                    UIPasteboard.general.string = game.worldReport
                    copiedReport = true
                } label: {
                    Label(copiedReport ? (cs ? "Zkopírováno" : "Copied") : (cs ? "Kopírovat" : "Copy"),
                          systemImage: copiedReport ? "checkmark" : "doc.on.doc")
                        .font(.caption.weight(.semibold))
                }
                .tint(Theme.accent)
            }
            Text(game.worldReport)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.textDim)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frontierCard()
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: cs ? "Poslední sezení" : "Last session")
            Text(diag.lastSummary)
                .font(.callout.monospaced())
                .foregroundStyle(Theme.text)
            Text("\(cs ? "Populace teď" : "Population now"): \(Int(game.world.totalPopulation)) · \(cs ? "rok" : "year") \(game.year)")
                .font(.caption).foregroundStyle(Theme.textDim)
        }
        .frontierCard()
    }

    private var simulateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: cs ? "Posunout čas (test)" : "Fast-forward (test)")
            Text(cs ? "Svět jinak běží jen na pozadí. Tímto vyvoláš eventy hned."
                    : "The world otherwise only advances in the background. This triggers events now.")
                .font(.caption).foregroundStyle(Theme.textDim)
            HStack(spacing: 10) {
                stepButton(cs ? "+1 rok" : "+1 yr", years: 1)
                stepButton(cs ? "+10 let" : "+10 yr", years: 10)
                stepButton(cs ? "+50 let" : "+50 yr", years: 50)
            }
            // A fight to watch, on demand. Otherwise a raid is a roll every few
            // years and half a minute long — see `GameViewModel.stageRaid`.
            Button {
                game.stageRaid()
                dismiss()
            } label: {
                Label(cs ? "Vyvolat nájezd" : "Stage a raid", systemImage: "flame.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(Theme.danger)
            .disabled(game.selectedSettlement?.siege != nil)

            if game.pendingProposal != nil {
                Label(cs ? "Čeká návrh zákona — vyřeš ho na tabu Sněm."
                         : "A law motion is waiting — resolve it on the Council tab.",
                      systemImage: "hand.raised.fill")
                    .font(.caption).foregroundStyle(Theme.accent)
            }
        }
        .frontierCard()
    }

    private func stepButton(_ title: String, years: Int) -> some View {
        Button {
            game.debugAdvance(ticks: years * game.ticksPerYear)
            copied = false
        } label: {
            Text(title).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(Theme.accent)
    }

    private var logCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: cs ? "Záznam" : "Log")
                Spacer()
                Button(cs ? "Vymazat" : "Clear") { diag.clear() }
                    .font(.caption).foregroundStyle(Theme.textDim)
            }
            if diag.entries.isEmpty {
                Text(cs ? "Zatím prázdné. Posuň čas a sleduj, co se stane."
                        : "Empty so far. Fast-forward and watch what happens.")
                    .font(.callout).foregroundStyle(Theme.textDim)
            } else {
                ForEach(diag.entries.reversed()) { entry in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: icon(entry.kind))
                            .font(.caption2).foregroundStyle(tint(entry.kind))
                            .frame(width: 16)
                        Text("y\(entry.year)")
                            .font(.caption2.monospaced()).foregroundStyle(Theme.textDim)
                            .frame(width: 34, alignment: .leading)
                        Text(entry.text)
                            .font(.caption).foregroundStyle(bodyTint(entry.kind))
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .frontierCard()
    }

    private func icon(_ kind: Diagnostics.Kind) -> String {
        switch kind {
        case .info: return "clock"
        case .birth: return "figure.child"
        case .arrival: return "figure.walk.arrival"
        case .death: return "xmark"
        case .event: return "sparkle"
        case .warning: return "exclamationmark.triangle.fill"
        case .tribe: return "flag.fill"
        }
    }

    private func tint(_ kind: Diagnostics.Kind) -> Color {
        switch kind {
        case .birth, .arrival: return Theme.good
        case .death: return Theme.danger
        case .warning: return Theme.accent
        case .tribe: return Theme.accent
        default: return Theme.textDim
        }
    }

    private func bodyTint(_ kind: Diagnostics.Kind) -> Color {
        kind == .warning ? Theme.accent : Theme.text
    }
}
