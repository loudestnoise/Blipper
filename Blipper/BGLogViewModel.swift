//
//  BGLogViewModel.swift
//  Blipper
//

import Foundation
import Observation

/// Fingerstick readings over a period, grouped by day for a log list.
@Observable
@MainActor
final class BGLogViewModel {
    struct Day: Identifiable {
        let date: Date
        let readings: [BGMReading]
        var id: Date { date }
    }

    private let provider: any TherapyDataProvider
    private let calendar: Calendar

    var period: TrendPeriod = .week {
        didSet { if period != oldValue { Task { await load() } } }
    }
    /// Start of the last day shown. Stepping back moves it by one period; changing the period keeps it.
    private(set) var endDay: Date
    /// The last day with a meter reading, when that is before today: periods open ending there
    /// and cannot step past it. `nil` when readings run through today or nothing is known.
    private(set) var dataEndDay: Date?
    private var hasResolvedDataEnd = false

    private(set) var readings: [BGMReading] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    init(provider: any TherapyDataProvider = MockTherapyProvider(), calendar: Calendar = .current) {
        self.provider = provider
        self.calendar = calendar
        self.endDay = calendar.startOfDay(for: Date())
    }

    var isCurrent: Bool { endDay >= calendar.startOfDay(for: Date()) }
    /// The newest day a period can end on.
    private var lastDay: Date { dataEndDay ?? calendar.startOfDay(for: Date()) }
    var canGoForward: Bool { endDay < lastDay }

    /// Whole calendar days: `period` days ending with `endDay`, through now when that is today.
    var interval: DateInterval {
        let end = isCurrent ? Date() : calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDay.addingTimeInterval(86_400)
        let start = calendar.date(byAdding: .day, value: -(period.days - 1), to: endDay) ?? endDay
        return DateInterval(start: start, end: end)
    }

    var stats: BGMStats { BGMStats(readings: readings) }

    /// Newest day first, newest reading first within a day.
    var days: [Day] {
        Dictionary(grouping: readings) { calendar.startOfDay(for: $0.timestamp) }
            .map { Day(date: $0.key, readings: $0.value.sorted { $0.timestamp > $1.timestamp }) }
            .sorted { $0.date > $1.date }
    }

    func previousPeriod() {
        guard let earlier = calendar.date(byAdding: .day, value: -period.days, to: endDay) else { return }
        moveTo(earlier)
    }

    func nextPeriod() {
        guard canGoForward, let later = calendar.date(byAdding: .day, value: period.days, to: endDay) else { return }
        moveTo(min(later, lastDay))
    }

    private func moveTo(_ day: Date) {
        endDay = calendar.startOfDay(for: day)
        readings = []
        Task { await load() }
    }

    /// Reloads, first checking again where the account's readings end in case more have arrived.
    func refresh() async {
        hasResolvedDataEnd = false
        await load()
    }

    private func resolveDataEnd() async {
        hasResolvedDataEnd = true
        let newest = try? await provider.latestFingerstickDate()
        let wasOnLastDay = endDay >= lastDay
        dataEndDay = DataEnd.day(newest: newest, calendar: calendar)
        if (wasOnLastDay || endDay > lastDay), endDay != lastDay {
            endDay = lastDay
            readings = []
        }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        if !hasResolvedDataEnd { await resolveDataEnd() }
        let requested = interval
        do {
            let loaded = try await provider.fingersticks(in: requested)
            // A slower, superseded request must not overwrite the period now shown.
            guard requested.start == interval.start else { return }
            readings = loaded
            errorMessage = nil
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
