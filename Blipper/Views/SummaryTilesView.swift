//
//  SummaryTilesView.swift
//  Blipper
//

import SwiftUI

struct SummaryTilesView: View {
    let stats: GlucoseStats

    var body: some View {
        HStack(spacing: 12) {
            StatTile(title: "In Range", value: percentText(stats.timeInRange), tint: .green)
            StatTile(title: "Average", value: averageText, unit: "mg/dL", tint: .blue)
            StatTile(title: "Readings", value: "\(stats.count)", tint: .secondary)
        }
    }

    private var averageText: String {
        guard let average = stats.average else { return "—" }
        return average.formatted(.number.precision(.fractionLength(0)))
    }

    private func percentText(_ fraction: Double?) -> String {
        guard let fraction else { return "—" }
        return fraction.formatted(.percent.precision(.fractionLength(0)))
    }

}

/// A small labeled number, used in rows of three.
struct StatTile: View {
    let title: String
    let value: String
    var unit: String? = nil
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title2.bold().monospacedDigit())
                    .foregroundStyle(tint)
                if let unit {
                    Text(unit)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}
