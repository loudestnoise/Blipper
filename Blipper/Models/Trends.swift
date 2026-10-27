//
//  Trends.swift
//  Blipper
//

import Foundation

/// One time-of-day bucket of an Ambulatory Glucose Profile.
nonisolated struct AGPBin: Identifiable, Sendable {
    /// Seconds after midnight at the bin's centre.
    let secondsOfDay: TimeInterval
    let p5: Double
    let p25: Double
    let median: Double
    let p75: Double
    let p95: Double
    let count: Int

    var id: TimeInterval { secondsOfDay }

    /// `secondsOfDay` placed on `day`, for plotting on a date axis.
    func time(on day: Date) -> Date { day.addingTimeInterval(secondsOfDay) }
}

nonisolated enum AGP {
    /// Folds every reading onto a single 24-hour clock in `binMinutes` buckets.
    /// Bins with fewer than `minimumCount` samples are dropped so sparse data doesn't draw spikes.
    static func profile(
        readings: [GlucoseReading],
        binMinutes: Int = 30,
        minimumCount: Int = 3,
        calendar: Calendar = .current
    ) -> [AGPBin] {
        let binSeconds = TimeInterval(binMinutes * 60)
        var buckets: [Int: [Double]] = [:]
        for reading in readings {
            let start = calendar.startOfDay(for: reading.timestamp)
            let seconds = reading.timestamp.timeIntervalSince(start)
            buckets[Int(seconds / binSeconds), default: []].append(reading.value)
        }
        return buckets.keys.sorted().compactMap { index in
            let values = buckets[index]!.sorted()
            guard values.count >= minimumCount else { return nil }
            return AGPBin(
                secondsOfDay: (Double(index) + 0.5) * binSeconds,
                p5: percentile(values, 0.05),
                p25: percentile(values, 0.25),
                median: percentile(values, 0.5),
                p75: percentile(values, 0.75),
                p95: percentile(values, 0.95),
                count: values.count
            )
        }
    }

    /// Linear-interpolated percentile of an ascending array.
    static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard let first = sorted.first, let last = sorted.last else { return .nan }
        guard sorted.count > 1 else { return first }
        let position = p * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = min(lower + 1, sorted.count - 1)
        let fraction = position - Double(lower)
        if lower == upper { return lower == sorted.count - 1 ? last : sorted[lower] }
        return sorted[lower] + (sorted[upper] - sorted[lower]) * fraction
    }
}

/// Stats for one calendar day, used by the per-day breakdown chart.
nonisolated struct DailyStats: Identifiable, Sendable {
    let day: Date
    let stats: GlucoseStats

    var id: Date { day }

    /// One entry per day in `interval`, including days with no readings.
    static func byDay(readings: [GlucoseReading], in interval: DateInterval, calendar: Calendar = .current) -> [DailyStats] {
        let grouped = Dictionary(grouping: readings) { calendar.startOfDay(for: $0.timestamp) }
        var result: [DailyStats] = []
        var day = calendar.startOfDay(for: interval.start)
        while day < interval.end {
            result.append(DailyStats(day: day, stats: GlucoseStats(readings: grouped[day] ?? [])))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }
}
