//
//  GlucoseViewModel.swift
//  Blipper
//

import Foundation
import Observation

/// Hours of data visible in the chart.
enum ChartWindow: Int, CaseIterable, Identifiable {
    case threeHours = 3
    case sixHours = 6
    case twelveHours = 12
    case day = 24

    var id: Int { rawValue }
    var label: String { "\(rawValue)h" }
}

@Observable
@MainActor
final class GlucoseViewModel {
    /// How often the day's readings are re-fetched automatically.
    static let refreshInterval: Duration = .seconds(5 * 60)

    private let provider: any GlucoseDataProvider
    private let calendar: Calendar

    /// Start of the day being displayed.
    private(set) var day: Date
    var window: ChartWindow = .sixHours {
        didSet { clearSelectionIfOutsideWindow() }
    }
    /// Time the user tapped or dragged to in the chart, if any.
    var selectedTime: Date?

    private(set) var dayReadings: [GlucoseReading] = []
    private(set) var isLoading = false
    private(set) var lastUpdated: Date?
    private(set) var errorMessage: String?

    init(provider: any GlucoseDataProvider = MockGlucoseProvider(), calendar: Calendar = .current) {
        self.provider = provider
        self.calendar = calendar
        self.day = calendar.startOfDay(for: Date())
    }

    // MARK: Derived state

    var isToday: Bool { calendar.isDateInToday(day) }
    var canGoForward: Bool { !isToday }

    var dayInterval: DateInterval {
        let end = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
        return DateInterval(start: day, end: end)
    }

    /// The visible span: the last `window` hours of the day, ending now for today.
    var windowInterval: DateInterval {
        let end = isToday ? min(Date(), dayInterval.end) : dayInterval.end
        let start = max(day, end.addingTimeInterval(-TimeInterval(window.rawValue) * 3600))
        return DateInterval(start: start, end: end)
    }

    var windowReadings: [GlucoseReading] {
        let interval = windowInterval
        return dayReadings.filter { interval.contains($0.timestamp) }
    }

    var stats: GlucoseStats { GlucoseStats(readings: windowReadings) }

    var latestReading: GlucoseReading? { windowReadings.last }

    /// The reading nearest to `selectedTime`, if one is within one sample gap.
    var selectedReading: GlucoseReading? {
        guard let selectedTime else { return nil }
        let nearest = windowReadings.min {
            abs($0.timestamp.timeIntervalSince(selectedTime)) < abs($1.timestamp.timeIntervalSince(selectedTime))
        }
        guard let nearest, abs(nearest.timestamp.timeIntervalSince(selectedTime)) <= 10 * 60 else { return nil }
        return nearest
    }

    /// What the header shows: the selection when there is one, otherwise the latest reading.
    var headerReading: GlucoseReading? { selectedReading ?? latestReading }

    // MARK: Actions

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            dayReadings = try await provider.readings(in: dayInterval)
            lastUpdated = Date()
            errorMessage = nil
        } catch is CancellationError {
            // Superseded by a newer load; keep what we have.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func previousDay() {
        guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { return }
        moveTo(previous)
    }

    func nextDay() {
        guard canGoForward, let next = calendar.date(byAdding: .day, value: 1, to: day) else { return }
        moveTo(next)
    }

    /// Reloads on a fixed interval until cancelled. Attach with `.task`.
    func autoRefresh() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.refreshInterval)
            guard !Task.isCancelled else { return }
            await load()
        }
    }

    private func moveTo(_ newDay: Date) {
        day = calendar.startOfDay(for: newDay)
        selectedTime = nil
        dayReadings = []
        Task { await load() }
    }

    private func clearSelectionIfOutsideWindow() {
        if let selectedTime, !windowInterval.contains(selectedTime) {
            self.selectedTime = nil
        }
    }
}
