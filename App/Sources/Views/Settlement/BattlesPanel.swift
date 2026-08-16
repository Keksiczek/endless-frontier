import SwiftUI
import EndlessFrontierCore

/// **The fights this colony remembers.**
///
/// Keks: *"battle logy nejdou nikde zobrazit."* He was right, and it was worse
/// than a missing screen — the colony kept exactly one record (`lastBattle`),
/// the report card was the only thing that could open it, and dismissing that
/// card put it away for good. A raid you glanced past was a raid the game no
/// longer had. `Settlement.battleHistory` keeps the last eight; this is where
/// you read them, and every one of them can be watched again.
struct BattlesPanel: View {
    @Bindable var game: GameViewModel

    private var cs: Bool { AppStrings.language == .cs }
    private func s(_ en: String, _ cz: String) -> String { cs ? cz : en }

    var body: some View {
        let fights = game.selectedSettlement?.battleHistory ?? []
        VStack(alignment: .leading, spacing: 8) {
            if fights.isEmpty {
                Text(s("Nobody has attacked this place yet.",
                       "Sem zatím nikdo nepřišel."))
                    .font(.caption)
                    .foregroundStyle(Theme.textDim)
            } else {
                ForEach(fights, id: \.id) { log in
                    row(log)
                    if log.id != fights.last?.id {
                        Divider().overlay(Theme.boneFaint.opacity(0.25))
                    }
                }
            }
        }
    }

    private func row(_ log: BattleLog) -> some View {
        let year = game.year(ofTick: log.tick)
        let dead = log.moments.count { $0.kind == .death }
        let hurt = log.moments.count { $0.kind == .wound }
        let plundered = log.moments.filter { $0.kind == .plunder }.reduce(0) { $0 + $1.amount }
        return Button {
            game.reopenBattle(log)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: log.repelled ? "shield.lefthalf.filled" : "flame.fill")
                        .font(.caption2)
                        .foregroundStyle(log.repelled ? Theme.good : Theme.danger)
                    Text(log.attackerLabel?.resolve(AppStrings.language) ?? log.attackerName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.text)
                    Spacer()
                    Text("\(AppStrings.year) \(year)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Theme.textDim)
                }
                // What it cost, in the two numbers anybody actually asks about.
                HStack(spacing: 8) {
                    Text(log.repelled ? s("Repelled", "Odraženo") : s("They got in", "Dostali se dovnitř"))
                    if dead > 0 { Text("· \(dead) \(s("dead", "mrtvých"))") }
                    if hurt > 0 { Text("· \(hurt) \(s("hurt", "raněných"))") }
                    if plundered > 1 { Text("· \(Int(plundered)) \(s("food taken", "jídla pryč"))") }
                }
                .font(.caption2)
                .foregroundStyle(Theme.textDim)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
