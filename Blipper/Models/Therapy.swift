//
//  Therapy.swift
//  Blipper
//
//  Insulin, carb, and fingerstick records that accompany CGM data.
//

import Foundation

/// A bolus delivery. `extended` is the square-wave portion delivered over `duration`.
nonisolated struct InsulinBolus: Identifiable, Hashable, Sendable {
    let timestamp: Date
    let normal: Double
    let extended: Double
    let duration: TimeInterval
    /// Delivered by a closed-loop controller rather than requested by the user.
    let automated: Bool

    var id: Date { timestamp }
    var total: Double { normal + extended }

    init(timestamp: Date, normal: Double, extended: Double = 0, duration: TimeInterval = 0, automated: Bool = false) {
        self.timestamp = timestamp
        self.normal = normal
        self.extended = extended
        self.duration = duration
        self.automated = automated
    }
}

/// A stretch of basal delivery at a constant rate (U/hr).
nonisolated struct BasalSegment: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case scheduled, temp, automated, suspend

        var label: String {
            switch self {
            case .scheduled: "Scheduled"
            case .temp: "Temp"
            case .automated: "Automated"
            case .suspend: "Suspended"
            }
        }
    }

    let start: Date
    let duration: TimeInterval
    let rate: Double
    let kind: Kind

    var id: Date { start }
    var end: Date { start.addingTimeInterval(duration) }
    var interval: DateInterval { DateInterval(start: start, duration: max(duration, 0)) }

    /// Units delivered during the part of this segment that overlaps `window`.
    func units(in window: DateInterval) -> Double {
        guard let overlap = interval.intersection(with: window) else { return 0 }
        return rate * overlap.duration / 3600
    }
}

/// Carbohydrates entered on a pump, in an app, or logged as food.
nonisolated struct CarbEntry: Identifiable, Hashable, Sendable {
    let timestamp: Date
    let grams: Double

    var id: Date { timestamp }
}

/// A blood glucose meter (fingerstick) reading, in mg/dL.
nonisolated struct BGMReading: Identifiable, Hashable, Sendable {
    enum Source: String, Sendable {
        case manual, meter

        var label: String {
            switch self {
            case .manual: "Manual"
            case .meter: "Meter"
            }
        }
    }

    let timestamp: Date
    let value: Double
    let source: Source

    var id: Date { timestamp }
    var range: GlucoseRange { GlucoseRange(value: value) }
}

/// Everything besides CGM for a span of time.
nonisolated struct TherapyData: Sendable {
    var boluses: [InsulinBolus] = []
    var basal: [BasalSegment] = []
    var carbs: [CarbEntry] = []
    var fingersticks: [BGMReading] = []

    static let empty = TherapyData()

    var isEmpty: Bool { boluses.isEmpty && basal.isEmpty && carbs.isEmpty && fingersticks.isEmpty }

    /// The subset that falls in (or, for basal, overlaps) `window`.
    func clipped(to window: DateInterval) -> TherapyData {
        TherapyData(
            boluses: boluses.filter { window.contains($0.timestamp) },
            basal: basal.filter { $0.interval.intersects(window) },
            carbs: carbs.filter { window.contains($0.timestamp) },
            fingersticks: fingersticks.filter { window.contains($0.timestamp) }
        )
    }

    var totalBolus: Double { boluses.reduce(0) { $0 + $1.total } }
    var totalCarbs: Double { carbs.reduce(0) { $0 + $1.grams } }

    func basalUnits(in window: DateInterval) -> Double {
        basal.reduce(0) { $0 + $1.units(in: window) }
    }

    /// The basal segment in effect at `time`, if any.
    func basalRate(at time: Date) -> BasalSegment? {
        basal.first { $0.start <= time && time < $0.end }
    }
}

/// Summary of a set of fingerstick readings.
nonisolated struct BGMStats: Sendable {
    let count: Int
    let average: Double?
    let inRange: Double?
    let lows: Int
    let highs: Int

    init(readings: [BGMReading]) {
        let total = readings.count
        count = total
        let ranges: [GlucoseRange] = readings.map(\.range)
        let inRangeCount: Int = ranges.filter { $0 == GlucoseRange.inRange }.count
        if total > 0 {
            let sum: Double = readings.reduce(0) { $0 + $1.value }
            average = sum / Double(total)
            inRange = Double(inRangeCount) / Double(total)
        } else {
            average = nil
            inRange = nil
        }
        lows = ranges.filter { $0 == GlucoseRange.low || $0 == GlucoseRange.veryLow }.count
        highs = ranges.filter { $0 == GlucoseRange.high || $0 == GlucoseRange.veryHigh }.count
    }
}
