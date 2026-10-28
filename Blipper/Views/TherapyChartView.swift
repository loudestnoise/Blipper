//
//  TherapyChartView.swift
//  Blipper
//
//  Two short charts stacked under the glucose chart and sharing its time axis:
//  boluses and carbs, then basal rate.
//

import Charts
import SwiftUI

/// Width reserved for trailing y-axis labels so stacked charts line up.
let chartAxisLabelWidth: CGFloat = 30

struct TherapyChartView: View {
    let therapy: TherapyData
    let interval: DateInterval
    @Binding var selectedTime: Date?

    static let bolusColor = Color(red: 0.00, green: 0.48, blue: 0.80)
    static let carbColor = Color(red: 0.95, green: 0.60, blue: 0.10)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            chartLabel("Insulin & Carbs", trailing: dosesSummary)
            dosesChart
                .frame(height: 90)

            chartLabel("Basal", trailing: basalSummary)
                .padding(.top, 10)
            basalChart
                .frame(height: 60)
        }
    }

    private var hourStride: Int { GlucoseChartView.hourStride(for: interval) }

    // MARK: Boluses and carbs

    /// Leaves room above the tallest bar and its label for the carb row along the top.
    private var bolusDomainTop: Double {
        let top = therapy.boluses.map(\.total).max() ?? 0
        return max(2, (top * 1.8 / 0.5).rounded(.up) * 0.5)
    }

    private var dosesChart: some View {
        let top = bolusDomainTop
        return Chart {
            // Automated (closed-loop) boluses are frequent and small, so they get thin unlabeled ticks.
            ForEach(therapy.boluses.filter(\.automated)) { bolus in
                BarMark(
                    x: .value("Time", bolus.timestamp),
                    y: .value("Units", bolus.total),
                    width: 2
                )
                .foregroundStyle(Self.bolusColor.opacity(0.45))
            }

            ForEach(therapy.boluses.filter { !$0.automated }) { bolus in
                BarMark(
                    x: .value("Time", bolus.timestamp),
                    y: .value("Units", bolus.total),
                    width: 5
                )
                .foregroundStyle(Self.bolusColor)
                .annotation(position: .top, spacing: 2) {
                    Text(bolus.total.formatted(.number.precision(.fractionLength(0...2))))
                        .font(.system(size: 9, weight: .medium).monospacedDigit())
                        .foregroundStyle(Self.bolusColor)
                }
            }

            // Carbs ride along the top of the plot so they never collide with the bars.
            ForEach(therapy.carbs) { entry in
                PointMark(
                    x: .value("Time", entry.timestamp),
                    y: .value("Units", top * 0.92)
                )
                .symbolSize(60)
                .foregroundStyle(Self.carbColor)
                .annotation(position: .trailing, spacing: 2) {
                    Text("\(Int(entry.grams.rounded()))g")
                        .font(.system(size: 9, weight: .medium).monospacedDigit())
                        .foregroundStyle(Self.carbColor)
                }
            }

            if let selectedTime {
                RuleMark(x: .value("Selected", selectedTime))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
        .chartXScale(domain: interval.start...interval.end)
        .chartYScale(domain: 0...top)
        .chartXSelection(value: $selectedTime)
        .chartXAxis { AxisMarks(values: .stride(by: .hour, count: hourStride)) { _ in AxisGridLine() } }
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0, top / 2].map { ($0 * 2).rounded() / 2 }) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let units = value.as(Double.self) {
                        Text(units.formatted(.number.precision(.fractionLength(0...1))) + "U")
                            .frame(width: chartAxisLabelWidth, alignment: .trailing)
                    }
                }
            }
        }
        .overlay {
            if therapy.boluses.isEmpty && therapy.carbs.isEmpty {
                emptyLabel("No insulin or carbs")
            }
        }
    }

    // MARK: Basal

    private var basalDomainTop: Double {
        let top = therapy.basal.map(\.rate).max() ?? 0
        return max(1, (top * 1.15 / 0.5).rounded(.up) * 0.5)
    }

    private var basalChart: some View {
        let top = basalDomainTop
        return Chart {
            ForEach(therapy.basal) { segment in
                RectangleMark(
                    xStart: .value("Start", max(segment.start, interval.start)),
                    xEnd: .value("End", min(segment.end, interval.end)),
                    yStart: .value("Zero", 0),
                    yEnd: .value("U/hr", segment.rate)
                )
                .foregroundStyle(Self.basalStyle(segment.kind))
            }

            if let selectedTime {
                RuleMark(x: .value("Selected", selectedTime))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
        .chartXScale(domain: interval.start...interval.end)
        .chartYScale(domain: 0...top)
        .chartXSelection(value: $selectedTime)
        .chartXAxis { AxisMarks(values: .stride(by: .hour, count: hourStride)) { _ in AxisGridLine() } }
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0, top]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let rate = value.as(Double.self) {
                        Text(rate.formatted(.number.precision(.fractionLength(0...1))))
                            .frame(width: chartAxisLabelWidth, alignment: .trailing)
                    }
                }
            }
        }
        .overlay {
            if therapy.basal.isEmpty {
                emptyLabel("No basal data")
            }
        }
    }

    static func basalStyle(_ kind: BasalSegment.Kind) -> Color {
        switch kind {
        case .scheduled: bolusColor.opacity(0.45)
        case .temp: .purple.opacity(0.6)
        case .automated: bolusColor.opacity(0.75)
        case .suspend: .red.opacity(0.35)
        }
    }

    // MARK: Labels

    private var dosesSummary: String {
        let bolus = therapy.totalBolus.formatted(.number.precision(.fractionLength(0...1)))
        let carbs = Int(therapy.totalCarbs.rounded())
        let automated = therapy.boluses.filter(\.automated).reduce(0) { $0 + $1.total }
        let auto = automated > 0 ? " (\(automated.formatted(.number.precision(.fractionLength(0...1)))) auto)" : ""
        return "\(bolus) U bolus\(auto) · \(carbs) g carbs"
    }

    private var basalSummary: String {
        let units = therapy.basalUnits(in: interval).formatted(.number.precision(.fractionLength(0...1)))
        return "\(units) U"
    }

    private func chartLabel(_ title: String, trailing: String) -> some View {
        HStack {
            Text(title)
                .font(.caption.weight(.semibold))
            Spacer()
            Text(trailing)
                .font(.caption.monospacedDigit())
        }
        .foregroundStyle(.secondary)
    }

    private func emptyLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.tertiary)
    }
}
