//
//  BGLogView.swift
//  Blipper
//
//  Fingerstick (blood glucose meter) readings as a day-by-day log.
//

import SwiftUI

struct BGLogView: View {
    @State private var model: BGLogViewModel

    init(provider: any TherapyDataProvider = MockTherapyProvider()) {
        _model = State(initialValue: BGLogViewModel(provider: provider))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DateNavigator(
                        title: rangeTitle,
                        unit: "period",
                        canGoForward: model.canGoForward,
                        onPrevious: model.previousPeriod,
                        onNext: model.nextPeriod
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                    Picker("Period", selection: $model.period) {
                        ForEach(TrendPeriod.allCases) { period in
                            Text(period.label).tag(period)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)

                    summary
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                if model.days.isEmpty {
                    Section {
                        if model.isLoading {
                            HStack { Spacer(); ProgressView(); Spacer() }
                        } else if let errorMessage = model.errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.red)
                        } else {
                            Text(model.isCurrent
                                 ? "No meter readings in the last \(model.period.days) days."
                                 : "No meter readings in this period.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                ForEach(model.days) { day in
                    Section {
                        ForEach(day.readings) { reading in
                            BGLogRow(reading: reading)
                        }
                    } header: {
                        Text(day.date, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                    }
                }

                Section {
                    Text("Not for treatment decisions.")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("BG Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if model.isLoading {
                        ProgressView()
                    }
                }
            }
            .refreshable { await model.refresh() }
            .task { await model.load() }
        }
    }

    private var rangeTitle: Text {
        let interval = model.interval
        // The interval ends at midnight after the last day unless it runs through now.
        let lastDay = interval.end.addingTimeInterval(-1)
        let showsYear = !Calendar.current.isDate(interval.start, equalTo: Date(), toGranularity: .year)
        let style = showsYear ? Date.FormatStyle.dateTime.month(.abbreviated).day().year() : .dateTime.month(.abbreviated).day()
        return Text("\(interval.start, format: style) – \(lastDay, format: style)")
    }

    private var summary: some View {
        let stats = model.stats
        return HStack(spacing: 12) {
            StatTile(title: "Readings", value: "\(stats.count)", tint: .secondary)
            StatTile(title: "Average", value: stats.average.map { $0.formatted(.number.precision(.fractionLength(0))) } ?? "—", unit: "mg/dL", tint: .blue)
            StatTile(title: "In Range", value: stats.inRange.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "—", tint: .green)
        }
    }
}

private struct BGLogRow: View {
    let reading: BGMReading

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(reading.range.color)
                .frame(width: 10, height: 10)
            Text(reading.timestamp, format: .dateTime.hour().minute())
                .monospacedDigit()
            Spacer()
            Text(reading.source.label)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(reading.value.formatted(.number.precision(.fractionLength(0))))
                    .font(.body.weight(.semibold).monospacedDigit())
                    .foregroundStyle(reading.range.color)
                Text("mg/dL")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 84, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(Int(reading.value)) milligrams per deciliter, \(reading.range.label), \(reading.source.label), \(reading.timestamp.formatted(.dateTime.hour().minute()))")
    }
}

#Preview {
    BGLogView()
}
