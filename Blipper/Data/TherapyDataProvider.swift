//
//  TherapyDataProvider.swift
//  Blipper
//

import Foundation

/// Source of insulin, carb, and fingerstick records.
nonisolated protocol TherapyDataProvider: Sendable {
    /// Boluses, basal segments, carbs, and fingersticks in `interval`.
    /// Basal segments that overlap the interval are included even if they start before it.
    func therapy(in interval: DateInterval) async throws -> TherapyData

    /// Fingerstick (meter) readings only, for longer spans.
    func fingersticks(in interval: DateInterval) async throws -> [BGMReading]
}

/// Loop-style therapy to go with `MockGlucoseProvider`: a bolus and carbs at each meal,
/// a scheduled basal with automated adjustments every 30 minutes, and a few fingersticks a day.
nonisolated struct MockTherapyProvider: TherapyDataProvider {
    var latency: Duration = .milliseconds(300)
    var calendar: Calendar = .current

    func therapy(in interval: DateInterval) async throws -> TherapyData {
        try await Task.sleep(for: latency)
        var data = TherapyData()
        forEachDay(in: interval) { day, profile, generator in
            let now = Date()
            for meal in profile.meals {
                let time = day.addingTimeInterval(meal.hour * 3600 - 10 * 60)
                guard time <= now else { continue }
                let grams = (meal.peak * 0.6 / 5).rounded() * 5
                let ratio = Double.random(in: 8...12, using: &generator)
                data.carbs.append(CarbEntry(timestamp: time, grams: grams))
                data.boluses.append(InsulinBolus(timestamp: time.addingTimeInterval(60), normal: (grams / ratio * 20).rounded() / 20))
            }
            // Occasional correction bolus mid-afternoon.
            if Bool.random(using: &generator) {
                let time = day.addingTimeInterval(15.5 * 3600)
                if time <= now { data.boluses.append(InsulinBolus(timestamp: time, normal: 1.0)) }
            }
            // Basal: 0.8 U/hr scheduled, modulated by an automated controller.
            let scheduled = 0.8
            var t = day
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
            while t < endOfDay && t <= now {
                let hours = t.timeIntervalSince(day) / 3600
                let glucose = profile.value(atHour: hours)
                let kind: BasalSegment.Kind
                let rate: Double
                switch glucose {
                case ..<80: kind = .suspend; rate = 0
                case ..<110: kind = .automated; rate = max(0, scheduled - Double.random(in: 0.2...0.6, using: &generator))
                case ..<150: kind = .scheduled; rate = scheduled
                default: kind = .automated; rate = scheduled + Double.random(in: 0.4...1.6, using: &generator)
                }
                data.basal.append(BasalSegment(start: t, duration: 30 * 60, rate: (rate * 20).rounded() / 20, kind: kind))
                // Closed-loop micro-boluses while high.
                if glucose > 160, Bool.random(using: &generator) {
                    data.boluses.append(InsulinBolus(timestamp: t.addingTimeInterval(5 * 60), normal: Double.random(in: 0.2...0.6, using: &generator), automated: true))
                }
                t = t.addingTimeInterval(30 * 60)
            }
            data.fingersticks += fingersticks(on: day, profile: profile, generator: &generator)
        }
        return data.clipped(to: interval)
    }

    func fingersticks(in interval: DateInterval) async throws -> [BGMReading] {
        try await Task.sleep(for: latency)
        var result: [BGMReading] = []
        forEachDay(in: interval) { day, profile, generator in
            result += fingersticks(on: day, profile: profile, generator: &generator)
        }
        return result.filter { interval.contains($0.timestamp) }
    }

    private func fingersticks(on day: Date, profile: DayProfile, generator: inout SeededGenerator) -> [BGMReading] {
        let now = Date()
        let count = Int.random(in: 1...3, using: &generator)
        var readings: [BGMReading] = []
        for _ in 0..<count {
            let hour = Double.random(in: 6...22, using: &generator)
            let time = day.addingTimeInterval((hour * 12).rounded() * 300)
            guard time <= now else { continue }
            let value = (profile.value(atHour: hour) + Double.random(in: -12...12, using: &generator)).rounded()
            let source: BGMReading.Source = Bool.random(using: &generator) ? .meter : .manual
            readings.append(BGMReading(timestamp: time, value: min(max(value, 40), 400), source: source))
        }
        return readings.sorted { $0.timestamp < $1.timestamp }
    }

    /// Walks each calendar day touching `interval` with that day's profile and a generator
    /// seeded separately from the glucose one, so the trace itself is unchanged.
    private func forEachDay(in interval: DateInterval, _ body: (Date, DayProfile, inout SeededGenerator) -> Void) {
        var day = calendar.startOfDay(for: interval.start)
        while day < interval.end {
            var profileGenerator = SeededGenerator(seed: UInt64(day.timeIntervalSince1970))
            let profile = DayProfile(generator: &profileGenerator)
            var generator = SeededGenerator(seed: UInt64(day.timeIntervalSince1970) ^ 0xC0FFEE)
            body(day, profile, &generator)
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
        }
    }
}
