//
//  TrendsViewModel.swift
//  Blipper
//

import Foundation
import Observation

enum TrendPeriod: Int, CaseIterable, Identifiable {
    case week = 7
    case twoWeeks = 14
    case month = 30
    case quarter = 90

    var id: Int { rawValue }
    var days: Int { rawValue }
    var label: String { "\(rawValue)d" }
    var longLabel: String { "\(rawValue) days" }
}

@Observable
@MainActor
final class TrendsViewModel {
    private let provider: any GlucoseDataProvider
    private let calendar: Calendar

    var period: TrendPeriod = .twoWeeks {
        didSet { if period != oldValue { Task { await load() } } }
    }
    /// Start of the last day shown. Stepping back moves it by one period; changing the period keeps it.
    private(set) var endDay: Date

    private(set) var readings: [GlucoseReading] = []
    private(set) var previousReadings: [GlucoseReading] = []
    private(set) var isLoading = false
    private(set) var lastUpdated: Date?
    private(set) var errorMessage: String?

    init(provider: any GlucoseDataProvider, calendar: Calendar = .current) {
        self.provider = provider
        self.calendar = calendar
        self.endDay = calendar.startOfDay(for: Date())
    }

    // MARK: Derived state

    var isCurrent: Bool { endDay >= calendar.startOfDay(for: Date()) }
    var canGoForward: Bool { !isCurrent }

    /// Whole calendar days: `period` days ending with `endDay`, through now when that is today.
    var interval: DateInterval {
        let end = isCurrent ? Date() : calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDay.addingTimeInterval(86_400)
        let start = calendar.date(byAdding: .day, value: -(period.rawValue - 1), to: endDay) ?? endDay
        return DateInterval(start: start, end: end)
    }

    /// The equal-length span immediately before `interval`, for the change indicator.
    var previousInterval: DateInterval {
        let current = interval
        let start = calendar.date(byAdding: .day, value: -period.rawValue, to: current.start)
            ?? current.start.addingTimeInterval(-current.duration)
        return DateInterval(start: start, end: current.start)
    }

    var stats: GlucoseStats { GlucoseStats(readings: readings) }
    var previousStats: GlucoseStats { GlucoseStats(readings: previousReadings) }

    /// Change in time-in-range versus the prior period, in percentage points.
    var timeInRangeChange: Double? {
        guard let current = stats.timeInRange, let previous = previousStats.timeInRange else { return nil }
        return (current - previous) * 100
    }

    var agp: [AGPBin] { AGP.profile(readings: readings, calendar: calendar) }

    var daily: [DailyStats] { DailyStats.byDay(readings: readings, in: interval, calendar: calendar) }

    // MARK: Actions

    func previousPeriod() {
        guard let earlier = calendar.date(byAdding: .day, value: -period.rawValue, to: endDay) else { return }
        moveTo(earlier)
    }

    func nextPeriod() {
        guard canGoForward, let later = calendar.date(byAdding: .day, value: period.rawValue, to: endDay) else { return }
        moveTo(min(later, calendar.startOfDay(for: Date())))
    }

    private func moveTo(_ day: Date) {
        endDay = calendar.startOfDay(for: day)
        readings = []
        previousReadings = []
        Task { await load() }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        let current = interval
        let previous = previousInterval
        do {
            // One request covers both spans; split locally.
            let all = try await provider.readings(in: DateInterval(start: previous.start, end: current.end))
            readings = all.filter { current.contains($0.timestamp) }
            previousReadings = all.filter { previous.contains($0.timestamp) }
            lastUpdated = Date()
            errorMessage = nil
        } catch is CancellationError {
            // Superseded; keep what we have.
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
