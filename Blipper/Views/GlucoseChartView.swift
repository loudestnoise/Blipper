//
//  GlucoseChartView.swift
//  Blipper
//

import Charts
import SwiftUI

struct GlucoseChartView: View {
    let readings: [GlucoseReading]
    var fingersticks: [BGMReading] = []
    let interval: DateInterval
    let selectedReading: GlucoseReading?
    @Binding var selectedTime: Date?

    private var yDomain: ClosedRange<Double> {
        let top = (readings.map(\.value) + fingersticks.map(\.value)).max() ?? 0
        return 40...max(300, (top / 50).rounded(.up) * 50)
    }

    private var hourStride: Int { Self.hourStride(for: interval) }

    /// Hours between vertical gridlines, shared with the therapy charts so they line up.
    static func hourStride(for interval: DateInterval) -> Int {
        let hours = interval.duration / 3600
        switch hours {
        case ..<8: return 1
        case ..<14: return 2
        default: return 4
        }
    }

    var body: some View {
        Chart {
            RectangleMark(
                xStart: .value("Start", interval.start),
                xEnd: .value("End", interval.end),
                yStart: .value("Low", GlucoseRange.targetLow),
                yEnd: .value("High", GlucoseRange.targetHigh)
            )
            .foregroundStyle(.green.opacity(0.12))

            ForEach(readings) { reading in
                LineMark(
                    x: .value("Time", reading.timestamp),
                    y: .value("mg/dL", reading.value)
                )
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .foregroundStyle(.blue)
            }

            // Fingersticks: hollow dots in the band color so they read apart from the CGM line.
            ForEach(fingersticks) { stick in
                PointMark(
                    x: .value("Time", stick.timestamp),
                    y: .value("mg/dL", stick.value)
                )
                .symbol {
                    Circle()
                        .strokeBorder(stick.range.color, lineWidth: 2)
                        .background(Circle().fill(Color(.systemBackground)))
                        .frame(width: 11, height: 11)
                }
            }

            if let selectedReading {
                // The header shows the selected value and time, so the rule stays bare.
                RuleMark(x: .value("Selected", selectedReading.timestamp))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))

                PointMark(
                    x: .value("Selected", selectedReading.timestamp),
                    y: .value("mg/dL", selectedReading.value)
                )
                .symbolSize(90)
                .foregroundStyle(.blue)
            }
        }
        .chartXScale(domain: interval.start...interval.end)
        .chartYScale(domain: yDomain)
        .chartXSelection(value: $selectedTime)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: hourStride)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .narrow)))
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: [40, 70, 120, 180, 250, 300]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let mgdl = value.as(Int.self) {
                        Text("\(mgdl)")
                            .frame(width: chartAxisLabelWidth, alignment: .trailing)
                    }
                }
            }
        }
        .frame(height: 260)
        .overlay {
            if readings.isEmpty {
                Text("No readings in this window")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
