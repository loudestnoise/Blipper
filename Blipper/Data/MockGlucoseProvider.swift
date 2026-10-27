//
//  MockGlucoseProvider.swift
//  Blipper
//

import Foundation

/// Generates plausible, deterministic CGM traces so the UI works offline.
/// The same calendar day always produces the same curve.
nonisolated struct MockGlucoseProvider: GlucoseDataProvider {
    /// Sample spacing, matching a typical CGM.
    var cadence: TimeInterval = 5 * 60
    /// Simulated network latency.
    var latency: Duration = .milliseconds(300)
    var calendar: Calendar = .current

    func readings(in interval: DateInterval) async throws -> [GlucoseReading] {
        try await Task.sleep(for: latency)

        let now = Date()
        var result: [GlucoseReading] = []
        var day = calendar.startOfDay(for: interval.start)

        while day < interval.end {
            let nextDay = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
            var generator = SeededGenerator(seed: UInt64(day.timeIntervalSince1970))
            let profile = DayProfile(generator: &generator)

            var t = day
            while t < nextDay && t <= now {
                if interval.contains(t) {
                    let hours = t.timeIntervalSince(day) / 3600
                    let noise = Double.random(in: -4...4, using: &generator)
                    let value = (profile.value(atHour: hours) + noise).rounded()
                    result.append(GlucoseReading(timestamp: t, value: min(max(value, 40), 400)))
                }
                t = t.addingTimeInterval(cadence)
            }
            day = nextDay
        }
        return result
    }
}

// MARK: - Curve shape

/// Baseline plus three meal excursions, with the parameters drawn per day.
nonisolated private struct DayProfile {
    struct Meal {
        let hour: Double
        let peak: Double
        let width: Double
    }

    let baseline: Double
    let drift: Double
    let meals: [Meal]

    init(generator: inout SeededGenerator) {
        baseline = Double.random(in: 95...125, using: &generator)
        drift = Double.random(in: -12...12, using: &generator)
        meals = [
            Meal(hour: Double.random(in: 7...8.5, using: &generator),
                 peak: Double.random(in: 40...110, using: &generator),
                 width: Double.random(in: 1.0...1.6, using: &generator)),
            Meal(hour: Double.random(in: 12...13.5, using: &generator),
                 peak: Double.random(in: 30...90, using: &generator),
                 width: Double.random(in: 1.0...1.8, using: &generator)),
            Meal(hour: Double.random(in: 18...19.5, using: &generator),
                 peak: Double.random(in: 50...130, using: &generator),
                 width: Double.random(in: 1.2...2.0, using: &generator)),
        ]
    }

    func value(atHour h: Double) -> Double {
        // Slow overnight dip and daytime rise.
        var v = baseline + drift * sin((h - 4) / 24 * 2 * .pi)
        // Occasional late-night low to exercise the lower bands.
        v -= 25 * exp(-pow((h - 3.0) / 1.2, 2))
        for meal in meals {
            // Asymmetric bump: fast rise, slower fall.
            let dt = h - meal.hour
            let sigma = dt < 0 ? meal.width * 0.5 : meal.width
            v += meal.peak * exp(-pow(dt / sigma, 2))
        }
        return v
    }
}

// MARK: - Deterministic RNG

/// SplitMix64, so a given seed always yields the same sequence.
nonisolated struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
