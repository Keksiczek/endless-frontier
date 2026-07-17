import SwiftUI
import EndlessFrontierCore

/// A tap-to-inspect card for a structure standing in the settlement: what it
/// is, what it gives the colony, and what it costs to keep standing. The
/// counterpart to `PawnInspectorCard` — the two share the canvas's bottom slot.
struct BuildingInspectorCard: View {
    let definition: BuildingDefinition
    let standing: Int
    let upkeep: Resources
    var synergies: [String] = []
    var onClose: () -> Void

    private var cs: Bool { AppStrings.language == .cs }

    private var descriptionText: String {
        definition.description.resolve(AppStrings.language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if !descriptionText.isEmpty {
                Text(descriptionText)
                    .font(.caption)
                    .foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            flows
            traits
            if !synergies.isEmpty { synergyRows }
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
                Text(definition.name)
                    .font(.system(.title3, design: .serif).weight(.semibold))
                    .foregroundStyle(Theme.text)
                Text("\(AppStrings.eraTitle(definition.era)) · \(standing)× \(cs ? "postaveno" : "standing")")
                    .font(.caption)
                    .foregroundStyle(Theme.textDim)
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

    /// What the building moves each tick, per instance: what it makes, what it
    /// burns to run, and what it costs merely to stand there.
    private var flows: some View {
        VStack(alignment: .leading, spacing: 6) {
            flowRow(cs ? "Vyrábí" : "Produces", definition.production, tint: Theme.good, sign: "+")
            flowRow(cs ? "Spotřebuje" : "Consumes", definition.consumption, tint: Theme.accent, sign: "−")
            flowRow(cs ? "Údržba" : "Upkeep", upkeep, tint: Theme.danger, sign: "−")
        }
    }

    @ViewBuilder
    private func flowRow(_ label: String, _ resources: Resources, tint: Color, sign: String) -> some View {
        let present = ResourceType.allCases.filter { resources[$0] > 0.001 }
        if !present.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.textDim)
                    .frame(width: 74, alignment: .leading)
                ForEach(present, id: \.self) { resource in
                    HStack(spacing: 3) {
                        Image(systemName: resource.symbolName).font(.caption2)
                        Text("\(sign)\(format(resources[resource]))")
                            .font(.caption.monospacedDigit())
                    }
                    .foregroundStyle(tint)
                    .accessibilityLabel("\(label) \(resource.displayName) \(format(resources[resource]))")
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// Upkeep runs to fractions (3% of a hut's 10 materials), so a plain Int
    /// would read as a flat zero on exactly the buildings that are cheapest to
    /// keep — show a decimal until the number is big enough not to need one.
    private func format(_ value: Double) -> String {
        value < 10 ? String(format: "%.1f", value) : "\(Int(value.rounded()))"
    }

    private var traits: some View {
        HStack(spacing: 14) {
            if definition.workers > 0 {
                trait(icon: "person.2.fill", text: "\(definition.workers)")
                    .accessibilityLabel("\(definition.workers) \(cs ? "pracovníků" : "workers")")
            }
            if definition.housing > 0 {
                trait(icon: "house.fill", text: "\(Int(definition.housing))")
                    .accessibilityLabel("\(cs ? "Bydlení" : "Housing") \(Int(definition.housing))")
            }
            if definition.storage > 0 {
                trait(icon: "archivebox.fill", text: "\(Int(definition.storage))")
                    .accessibilityLabel("\(cs ? "Sklad" : "Storage") \(Int(definition.storage))")
            }
            if definition.defense > 0 {
                trait(icon: "shield.fill", text: "\(Int(definition.defense))")
            }
            if definition.pollution > 0 {
                trait(icon: "smoke.fill", text: "\(Int(definition.pollution))")
            }
            Spacer(minLength: 0)
        }
    }

    private func trait(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.caption2)
            Text(text).font(.caption.monospacedDigit())
        }
        .foregroundStyle(Theme.textDim)
    }

    /// The layout bonuses this building earns next to the right neighbours.
    private var synergyRows: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(cs ? "Sousedství" : "Adjacency")
                .font(.caption2.weight(.bold)).tracking(1.2)
                .foregroundStyle(Theme.textDim)
            ForEach(synergies, id: \.self) { line in
                HStack(spacing: 5) {
                    Image(systemName: "square.grid.3x3.topleft.filled")
                        .font(.system(size: 8))
                        .foregroundStyle(Theme.accent.opacity(0.8))
                    Text(line)
                        .font(.caption2)
                        .foregroundStyle(Theme.textDim)
                }
            }
        }
    }
}
