//
//  ContentView.swift
//  Blipper
//
//  Created by David Cintron on 10/27/26.
//

import SwiftUI

struct ContentView: View {
    @State private var model: GlucoseViewModel

    init(provider: any GlucoseDataProvider = MockGlucoseProvider()) {
        _model = State(initialValue: GlucoseViewModel(provider: provider))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ReadingHeader(reading: model.headerReading, isSelection: model.selectedReading != nil)

                    DayNavigator(
                        day: model.day,
                        canGoForward: model.canGoForward,
                        onPrevious: model.previousDay,
                        onNext: model.nextDay
                    )

                    Picker("Window", selection: $model.window) {
                        ForEach(ChartWindow.allCases) { window in
                            Text(window.label).tag(window)
                        }
                    }
                    .pickerStyle(.segmented)

                    GlucoseChartView(
                        readings: model.windowReadings,
                        interval: model.windowInterval,
                        selectedReading: model.selectedReading,
                        selectedTime: $model.selectedTime
                    )

                    SummaryTilesView(stats: model.stats)

                    RangeBreakdownView(stats: model.stats)

                    if let errorMessage = model.errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    footer
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Blipper")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    BlipperWordmark()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if model.isLoading {
                        ProgressView()
                    }
                }
            }
            .refreshable { await model.load() }
            .task { await model.load() }
            .task { await model.autoRefresh() }
        }
    }

    private var footer: some View {
        VStack(spacing: 4) {
            if let lastUpdated = model.lastUpdated {
                Text("Updated \(lastUpdated, format: .dateTime.hour().minute())")
            }
            Text("Not for treatment decisions.")
                .fontWeight(.semibold)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }
}

// MARK: - Wordmark

/// "Blipper" in the logo's rounded bold blue, for use as a title.
struct BlipperWordmark: View {
    static let blue = Color(red: 0.11, green: 0.37, blue: 0.65)

    var body: some View {
        Text("Blipper")
            .font(.system(size: 24, weight: .heavy, design: .rounded))
            .foregroundStyle(Self.blue)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Header

private struct ReadingHeader: View {
    let reading: GlucoseReading?
    let isSelection: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(reading.map { $0.value.formatted(.number.precision(.fractionLength(0))) } ?? "—")
                    .font(.system(size: 48, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(reading.map(\.range.color) ?? .secondary)
                Text("mg/dL")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.default, value: reading)
    }

    private var subtitle: String {
        guard let reading else { return "No data" }
        let time = reading.timestamp.formatted(.dateTime.hour().minute())
        return isSelection ? "Selected · \(time)" : "Latest · \(time)"
    }
}

// MARK: - Day navigation

private struct DayNavigator: View {
    let day: Date
    let canGoForward: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack {
            Button(action: onPrevious) {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("Previous day")
            Spacer()
            Text(day, format: .dateTime.weekday(.wide).month().day())
                .font(.headline)
            Spacer()
            Button(action: onNext) {
                Image(systemName: "chevron.right")
            }
            .disabled(!canGoForward)
            .accessibilityLabel("Next day")
        }
        .buttonStyle(.bordered)
    }
}

#Preview {
    ContentView()
}
