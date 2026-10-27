//
//  TrendsView.swift
//  Blipper
//

import Charts
import SwiftUI

struct TrendsView: View {
    @State private var model: TrendsViewModel

    init(provider: any GlucoseDataProvider = MockGlucoseProvider()) {
        _model = State(initialValue: TrendsViewModel(provider: provider))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Period", selection: $model.period) {
                        ForEach(TrendPeriod.allCases) { period in
                            Text(period.label).tag(period)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(model.interval.start, format: .dateTime.month(.abbreviated).day())
                        + Text(" – ")
                        + Text(model.interval.end, format: .dateTime.month(.abbreviated).day())

                    TimeInRangeCard(stats: model.stats, change: model.timeInRangeChange, period: model.period)

                    StatGrid(stats: model.stats)

                    AGPCard(bins: model.agp, readingCount: model.stats.count)

                    DailyRangeCard(days: model.daily)

                    if let errorMessage = model.errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    Text("Not for treatment decisions.")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Trends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if model.isLoading {
                        ProgressView()
                    }
                }
            }
            .refreshable { await model.load() }
            .task { await model.load() }
        }
    }
}

// MARK: - Time in range

private struct TimeInRangeCard: View {
    let stats: GlucoseStats
    let change: Double?
    let period: TrendPeriod

    /// Stacked low-to-high, matching the chart's vertical order when read left to right.
    private let order: [GlucoseRange] = [.veryLow, .low, .inRange, .high, .veryHigh]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Time in Range")
                        .font(.headline)
                    Text("Target 70–180 mg/dL")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(stats.timeInRange.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "—")
                        .font(.system(size: 36, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.green)
                    changeLabel
                }
            }

            if stats.count > 0 {
                GeometryReader { proxy in
                    HStack(spacing: 2) {
                        ForEach(order) { range in
                            let fraction = stats.fraction(of: range)
                            if fraction > 0 {
                                Rectangle()
                                    .fill(range.color)
                                    .frame(width: max(3, proxy.size.width * fraction))
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .frame(height: 18)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.tertiarySystemFill))
                    .frame(height: 18)
            }

            HStack(alignment: .top, spacing: 0) {
                ForEach(order) { range in
                    VStack(spacing: 2) {
                        Text(stats.fraction(of: range), format: .percent.precision(.fractionLength(0)))
                            .font(.subheadline.bold().monospacedDigit())
                        Text(range.label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Circle()
                            .fill(range.color)
                            .frame(width: 6, height: 6)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var changeLabel: some View {
        if let change {
            let symbol = change > 0.5 ? "arrow.up" : change < -0.5 ? "arrow.down" : "minus"
            let tint: Color = change > 0.5 ? .green : change < -0.5 ? .orange : .secondary
            Label {
                Text(abs(change), format: .number.precision(.fractionLength(0)))
                    + Text(" pts vs prior \(period.longLabel)")
            } icon: {
                Image(systemName: symbol)
            }
            .font(.caption)
            .foregroundStyle(tint)
        } else {
            Text("No prior period")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Stats

private struct StatGrid: View {
    let stats: GlucoseStats

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            tile("Average", value: number(stats.average), unit: "mg/dL")
            tile("Std. Deviation", value: number(stats.standardDeviation), unit: "mg/dL")
            tile("CV", value: stats.coefficientOfVariation.map { $0.formatted(.percent.precision(.fractionLength(0))) },
                 unit: nil, footnote: "goal ≤ 36%")
            tile("GMI", value: stats.gmi.map { $0.formatted(.number.precision(.fractionLength(1))) },
                 unit: "%", footnote: "\(stats.count) readings")
        }
    }

    private func number(_ value: Double?) -> String? {
        value.map { $0.formatted(.number.precision(.fractionLength(0))) }
    }

    private func tile(_ title: String, value: String?, unit: String?, footnote: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value ?? "—")
                    .font(.title2.bold().monospacedDigit())
                if let unit, value != nil {
                    Text(unit)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if let footnote {
                Text(footnote)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - AGP

private struct AGPCard: View {
    let bins: [AGPBin]
    let readingCount: Int

    private let day = Calendar.current.startOfDay(for: Date())

    private var yTop: Double {
        max(300, ((bins.map(\.p95).max() ?? 0) / 50).rounded(.up) * 50)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ambulatory Glucose Profile")
                .font(.headline)
            Text("Every day folded onto one 24-hour clock")
                .font(.caption)
                .foregroundStyle(.secondary)

            Chart {
                RectangleMark(
                    xStart: .value("Start", day),
                    xEnd: .value("End", day.addingTimeInterval(86_400)),
                    yStart: .value("Low", GlucoseRange.targetLow),
                    yEnd: .value("High", GlucoseRange.targetHigh)
                )
                .foregroundStyle(.green.opacity(0.10))

                ForEach(bins) { bin in
                    AreaMark(
                        x: .value("Time", bin.time(on: day)),
                        yStart: .value("5th", bin.p5),
                        yEnd: .value("95th", bin.p95),
                        series: .value("Band", "outer")
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(.blue.opacity(0.15))

                    AreaMark(
                        x: .value("Time", bin.time(on: day)),
                        yStart: .value("25th", bin.p25),
                        yEnd: .value("75th", bin.p75),
                        series: .value("Band", "inner")
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(.blue.opacity(0.30))

                    LineMark(
                        x: .value("Time", bin.time(on: day)),
                        y: .value("Median", bin.median),
                        series: .value("Line", "median")
                    )
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .foregroundStyle(.blue)
                }

                RuleMark(y: .value("Target low", GlucoseRange.targetLow))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(.green.opacity(0.6))
                RuleMark(y: .value("Target high", GlucoseRange.targetHigh))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(.green.opacity(0.6))
            }
            .chartXScale(domain: day...day.addingTimeInterval(86_400))
            .chartYScale(domain: 40...yTop)
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .narrow)))
                }
            }
            .chartYAxis {
                AxisMarks(values: [40, 70, 120, 180, 250, 300]) { _ in
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
            .frame(height: 220)
            .overlay {
                if bins.isEmpty {
                    Text(readingCount == 0 ? "No readings in this period" : "Not enough data yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 14) {
                legend(color: .blue, label: "Median")
                legend(color: .blue.opacity(0.30), label: "25–75%")
                legend(color: .blue.opacity(0.15), label: "5–95%")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func legend(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 14, height: 8)
            Text(label)
        }
    }
}

// MARK: - Per-day breakdown

private struct DailyRangeCard: View {
    let days: [DailyStats]

    private let order: [GlucoseRange] = [.veryLow, .low, .inRange, .high, .veryHigh]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Time in Range by Day")
                .font(.headline)

            Chart {
                ForEach(days) { day in
                    ForEach(order) { range in
                        BarMark(
                            x: .value("Day", day.day, unit: .day),
                            y: .value("Share", day.stats.fraction(of: range))
                        )
                        .foregroundStyle(by: .value("Range", range.label))
                    }
                }
            }
            .chartForegroundStyleScale(
                domain: order.map(\.label),
                range: order.map(\.color)
            )
            .chartLegend(.hidden)
            .chartYScale(domain: 0...1)
            .chartYAxis {
                AxisMarks(values: [0, 0.5, 1]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(v, format: .percent.precision(.fractionLength(0)))
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: days.count > 31 ? 14 : days.count > 14 ? 7 : days.count > 7 ? 2 : 1)) { _ in
                    AxisValueLabel(format: days.count > 7 ? .dateTime.month(.abbreviated).day() : .dateTime.weekday(.abbreviated))
                }
            }
            .frame(height: 160)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    TrendsView()
}
