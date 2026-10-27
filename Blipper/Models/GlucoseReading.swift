//
//  GlucoseReading.swift
//  Blipper
//

import Foundation

/// A single continuous-glucose-monitor sample, in mg/dL.
nonisolated struct GlucoseReading: Identifiable, Hashable, Sendable {
    let timestamp: Date
    let value: Double

    var id: Date { timestamp }

    var range: GlucoseRange { GlucoseRange(value: value) }
}

/// The five clinical glucose bands used for the range breakdown.
nonisolated enum GlucoseRange: CaseIterable, Identifiable, Sendable {
    case veryLow
    case low
    case inRange
    case high
    case veryHigh

    var id: Self { self }

    static let targetLow: Double = 70
    static let targetHigh: Double = 180

    init(value: Double) {
        switch value {
        case ..<54: self = .veryLow
        case ..<Self.targetLow: self = .low
        case ...Self.targetHigh: self = .inRange
        case ...250: self = .high
        default: self = .veryHigh
        }
    }

    var label: String {
        switch self {
        case .veryLow: "Very Low"
        case .low: "Low"
        case .inRange: "In Range"
        case .high: "High"
        case .veryHigh: "Very High"
        }
    }

    var bounds: String {
        switch self {
        case .veryLow: "< 54"
        case .low: "54–69"
        case .inRange: "70–180"
        case .high: "181–250"
        case .veryHigh: "> 250"
        }
    }
}

/// Aggregate statistics for a set of readings.
nonisolated struct GlucoseStats: Sendable {
    let count: Int
    let average: Double?
    let standardDeviation: Double?
    let timeInRange: Double?
    let breakdown: [GlucoseRange: Double]

    static let empty = GlucoseStats(count: 0, average: nil, standardDeviation: nil, timeInRange: nil, breakdown: [:])

    init(count: Int, average: Double?, standardDeviation: Double?, timeInRange: Double?, breakdown: [GlucoseRange: Double]) {
        self.count = count
        self.average = average
        self.standardDeviation = standardDeviation
        self.timeInRange = timeInRange
        self.breakdown = breakdown
    }

    init(readings: [GlucoseReading]) {
        guard !readings.isEmpty else {
            self = .empty
            return
        }
        let total = Double(readings.count)
        var counts: [GlucoseRange: Int] = [:]
        for reading in readings {
            counts[reading.range, default: 0] += 1
        }
        count = readings.count
        let mean = readings.map(\.value).reduce(0, +) / total
        average = mean
        standardDeviation = readings.count > 1
            ? (readings.map { ($0.value - mean) * ($0.value - mean) }.reduce(0, +) / (total - 1)).squareRoot()
            : nil
        breakdown = Dictionary(uniqueKeysWithValues: GlucoseRange.allCases.map { range in
            (range, Double(counts[range, default: 0]) / total)
        })
        timeInRange = breakdown[.inRange]
    }

    /// Coefficient of variation, 0...1. Under 0.36 is the usual stability target.
    var coefficientOfVariation: Double? {
        guard let average, let standardDeviation, average > 0 else { return nil }
        return standardDeviation / average
    }

    /// Glucose Management Indicator (%), Bergenstal et al. 2018: 3.31 + 0.02392 × mean mg/dL.
    var gmi: Double? {
        average.map { 3.31 + 0.02392 * $0 }
    }

    /// Fraction of readings in `range`, 0...1.
    func fraction(of range: GlucoseRange) -> Double {
        breakdown[range, default: 0]
    }
}
