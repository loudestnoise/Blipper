//
//  RangeBreakdownView.swift
//  Blipper
//

import SwiftUI

struct RangeBreakdownView: View {
    let stats: GlucoseStats

    /// Shown with the highest band first, matching the chart's vertical order.
    private let order: [GlucoseRange] = [.veryHigh, .high, .inRange, .low, .veryLow]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Range Breakdown")
                .font(.headline)
            ForEach(order) { range in
                row(range)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func row(_ range: GlucoseRange) -> some View {
        let fraction = stats.fraction(of: range)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text(range.label)
                    .font(.subheadline)
                Text(range.bounds)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 84, alignment: .leading)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.tertiarySystemFill))
                    Capsule()
                        .fill(range.color)
                        .frame(width: max(fraction > 0 ? 4 : 0, proxy.size.width * fraction))
                }
            }
            .frame(height: 10)

            Text(fraction, format: .percent.precision(.fractionLength(0)))
                .font(.subheadline.monospacedDigit())
                .frame(width: 44, alignment: .trailing)
        }
    }
}

extension GlucoseRange {
    var color: Color {
        switch self {
        case .veryLow: .red
        case .low: .orange
        case .inRange: .green
        case .high: .yellow
        case .veryHigh: .orange
        }
    }
}
