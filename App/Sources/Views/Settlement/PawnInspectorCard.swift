import SwiftUI
import EndlessFrontierCore

/// A tap-to-inspect card for a single colonist: who they are, how they fare,
/// and their inherited disposition. Slides up over the living canvas.
struct PawnInspectorCard: View {
    let pawn: Pawn
    let ticksPerYear: Int
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            HStack(spacing: 10) {
                vital(icon: "heart.fill", label: "HP", value: pawn.health, tint: Theme.good)
                vital(icon: "face.smiling", label: AppStrings.language == .cs ? "Nálada" : "Mood",
                      value: pawn.mood, tint: Theme.accent)
                if pawn.wealth > 0 {
                    vital(icon: "circle.hexagongrid.fill",
                          label: AppStrings.language == .cs ? "Jmění" : "Wealth",
                          value: nil, text: "\(Int(pawn.wealth))", tint: Theme.textDim)
                }
            }
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
