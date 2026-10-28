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
        didSet { Task { await load() } }
    }

    private(set) var readings: [BGMReading] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    init(provider: any TherapyDataProvider = MockTherapyProvider(), calendar: Calendar = .current) {
        self.provider = provider
        self.calendar = calendar
    }

    var interval: DateInterval {
        let end = Date()
        let start = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -(period.days - 1), to: end) ?? end)
        return DateInterval(start: start, end: end)
    }

    var stats: BGMStats { BGMStats(readings: readings) }

    /// Newest day first, newest reading first within a day.
    var days: [Day] {
        Dictionary(grouping: readings) { calendar.startOfDay(for: $0.timestamp) }
            .map { Day(date: $0.key, readings: $0.value.sorted { $0.timestamp > $1.timestamp }) }
            .sorted { $0.date > $1.date }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            readings = try await provider.fingersticks(in: interval)
            errorMessage = nil
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
