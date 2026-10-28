//
//  TherapyTilesView.swift
//  Blipper
//

import SwiftUI

/// Insulin and carb totals for the visible window.
struct TherapyTilesView: View {
    let therapy: TherapyData
    let interval: DateInterval

    var body: some View {
        HStack(spacing: 12) {
            StatTile(title: "Bolus", value: units(therapy.totalBolus), unit: "U", tint: TherapyChartView.bolusColor)
            StatTile(title: "Basal", value: units(therapy.basalUnits(in: interval)), unit: "U", tint: TherapyChartView.bolusColor.opacity(0.7))
            StatTile(title: "Carbs", value: "\(Int(therapy.totalCarbs.rounded()))", unit: "g", tint: TherapyChartView.carbColor)
        }
    }

    private func units(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }
}

/// One caption under a scrubbed point: basal in effect plus any nearby bolus, carbs, or fingerstick.
struct SelectedEventsLabel: View {
    let events: GlucoseViewModel.SelectedEvents

    var body: some View {
        HStack(spacing: 12) {
            if let basal = events.basal {
                item("drop.fill", "\(basal.rate.formatted(.number.precision(.fractionLength(0...2)))) U/hr", basal.kind.label, TherapyChartView.basalStyle(basal.kind))
            }
            if events.bolus > 0 {
                item("syringe.fill", "\(events.bolus.formatted(.number.precision(.fractionLength(0...2)))) U", "bolus", TherapyChartView.bolusColor)
            }
            if events.carbs > 0 {
                item("fork.knife", "\(Int(events.carbs.rounded())) g", "carbs", TherapyChartView.carbColor)
            }
            if let stick = events.fingerstick {
                item("drop.circle", "\(Int(stick.value))", "fingerstick", stick.range.color)
            }
            Spacer(minLength: 0)
        }
        .font(.caption.monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private func item(_ symbol: String, _ value: String, _ caption: String, _ tint: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
            Text(value)
                .fontWeight(.semibold)
            Text(caption)
                .foregroundStyle(.secondary)
        }
    }
}
