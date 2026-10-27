//
//  SummaryTilesView.swift
//  Blipper
//

import SwiftUI

struct SummaryTilesView: View {
    let stats: GlucoseStats

    var body: some View {
        HStack(spacing: 12) {
            tile(title: "In Range", value: percentText(stats.timeInRange), tint: .green)
            tile(title: "Average", value: averageText, unit: "mg/dL", tint: .blue)
            tile(title: "Readings", value: "\(stats.count)", tint: .secondary)
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

    private func tile(title: String, value: String, unit: String? = nil, tint: Color) -> some View {
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
