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
    private let therapyProvider: (any TherapyDataProvider)?
    private let calendar: Calendar

    /// Start of the day being displayed.
    private(set) var day: Date
    /// The last day with any data, when that is before today: the screen opens there and cannot
    /// step past it. `nil` when data runs through today or nothing is known.
    private(set) var dataEndDay: Date?
    /// When the newest record on `dataEndDay` was made, so the chart can end there, not at midnight.
    private var dataEndTime: Date?
    private var hasResolvedDataEnd = false
    var window: ChartWindow = .sixHours {
        didSet { clearSelectionIfOutsideWindow() }
    }
    /// Time the user tapped or dragged to in the chart, if any.
    var selectedTime: Date?

    private(set) var dayReadings: [GlucoseReading] = []
    private(set) var dayTherapy: TherapyData = .empty
    private(set) var isLoading = false
    private(set) var lastUpdated: Date?
    private(set) var errorMessage: String?

    init(
        provider: any GlucoseDataProvider = MockGlucoseProvider(),
        therapyProvider: (any TherapyDataProvider)? = MockTherapyProvider(),
        calendar: Calendar = .current
    ) {
        self.provider = provider
        self.therapyProvider = therapyProvider
        self.calendar = calendar
        self.day = calendar.startOfDay(for: Date())
    }

    var hasTherapy: Bool { therapyProvider != nil }

    // MARK: Derived state

    var isToday: Bool { calendar.isDateInToday(day) }
    /// The newest day that can be shown.
    private var lastDay: Date { dataEndDay ?? calendar.startOfDay(for: Date()) }
    var canGoForward: Bool { day < lastDay }

    var dayInterval: DateInterval {
        let end = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
        return DateInterval(start: day, end: end)
    }

    /// The visible span: the last `window` hours of the day, ending now for today.
    var windowInterval: DateInterval {
        var end = isToday ? min(Date(), dayInterval.end) : dayInterval.end
        // On the last day with data the window ends at the newest record, as today's ends at now.
        if let dataEndTime, day == dataEndDay { end = min(end, max(dataEndTime, day.addingTimeInterval(3600))) }
        let start = max(day, end.addingTimeInterval(-TimeInterval(window.rawValue) * 3600))
        return DateInterval(start: start, end: end)
    }

    var windowReadings: [GlucoseReading] {
        let interval = windowInterval
        return dayReadings.filter { interval.contains($0.timestamp) }
    }

    var windowTherapy: TherapyData { dayTherapy.clipped(to: windowInterval) }

    var stats: GlucoseStats { GlucoseStats(readings: windowReadings) }

    /// Therapy events near `selectedTime`: the basal rate in effect, and any bolus or carbs
    /// within 15 minutes, for a one-line caption under the chart.
    var selectedEvents: SelectedEvents? {
        guard let selectedTime else { return nil }
        let tolerance: TimeInterval = 15 * 60
        let therapy = windowTherapy
        return SelectedEvents(
            basal: therapy.basalRate(at: selectedTime),
            bolus: therapy.boluses.filter { abs($0.timestamp.timeIntervalSince(selectedTime)) <= tolerance }.reduce(0) { $0 + $1.total },
            carbs: therapy.carbs.filter { abs($0.timestamp.timeIntervalSince(selectedTime)) <= tolerance }.reduce(0) { $0 + $1.grams },
            fingerstick: therapy.fingersticks.first { abs($0.timestamp.timeIntervalSince(selectedTime)) <= tolerance }
        )
    }

    struct SelectedEvents {
        let basal: BasalSegment?
        let bolus: Double
        let carbs: Double
        let fingerstick: BGMReading?

        var isEmpty: Bool { basal == nil && bolus == 0 && carbs == 0 && fingerstick == nil }
    }

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
        if !hasResolvedDataEnd { await resolveDataEnd() }
        do {
            let interval = dayInterval
            async let readings = provider.readings(in: interval)
            async let therapy = therapyProvider?.therapy(in: interval) ?? .empty
            (dayReadings, dayTherapy) = try await (readings, therapy)
            lastUpdated = Date()
            errorMessage = nil
        } catch is CancellationError {
            // Superseded by a newer load; keep what we have.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Reloads, first checking again where the account's data ends in case more has arrived.
    func refresh() async {
        hasResolvedDataEnd = false
        await load()
    }

    /// Finds the newest day with data. A screen sitting on the newest day follows it; one the
    /// user has stepped back from stays put.
    private func resolveDataEnd() async {
        hasResolvedDataEnd = true
        async let glucose = provider.latestReadingDate()
        async let therapy = therapyProvider?.latestTherapyDate()
        // A failed lookup just means no limit; the data load reports real errors.
        let newest = [try? await glucose, try? await therapy].compactMap { $0 }.max()
        let wasOnLastDay = day >= lastDay
        dataEndDay = DataEnd.day(newest: newest, calendar: calendar)
        dataEndTime = dataEndDay == nil ? nil : newest
        if (wasOnLastDay || day > lastDay), day != lastDay {
            day = lastDay
            selectedTime = nil
            dayReadings = []
            dayTherapy = .empty
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
            await refresh()
        }
    }

    private func moveTo(_ newDay: Date) {
        day = calendar.startOfDay(for: newDay)
        selectedTime = nil
        dayReadings = []
        dayTherapy = .empty
        Task { await load() }
    }

    private func clearSelectionIfOutsideWindow() {
        if let selectedTime, !windowInterval.contains(selectedTime) {
            self.selectedTime = nil
        }
    }
}
