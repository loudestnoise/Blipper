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
    /// A moment to mark with a vertical line, such as a note's time.
    var marker: Date? = nil
    /// When set, the chart shows part of `interval` and scrolls sideways instead of selecting.
    var scroll: ChartScroll? = nil
    var height: CGFloat = 260

    private var yDomain: ClosedRange<Double> {
        let top = (readings.map(\.value) + fingersticks.map(\.value)).max() ?? 0
        return 40...max(300, (top / 50).rounded(.up) * 50)
    }

    private var hourStride: Int { Self.hourStride(for: scroll?.visibleInterval ?? interval) }

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

            if let marker {
                RuleMark(x: .value("Marker", marker))
                    .foregroundStyle(Color.primary.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 2))

                PointMark(
                    x: .value("Marker", marker),
                    y: .value("mg/dL", yDomain.upperBound - 14)
                )
                .symbol {
                    Image(systemName: "note.text")
                        .font(.caption.weight(.semibold))
                        .padding(3)
                        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 4))
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
        .chartXInteraction(scroll: scroll, selection: $selectedTime)
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
        .frame(height: height)
        .overlay {
            if readings.isEmpty {
                Text("No readings in this window")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Scrolling

/// Sideways scrolling for a chart that shows part of a longer span. Charts given the same
/// `position` binding scroll together.
struct ChartScroll {
    let visibleLength: TimeInterval
    /// The leading edge of the visible part.
    let position: Binding<Date>

    var visibleInterval: DateInterval { DateInterval(start: position.wrappedValue, duration: visibleLength) }
}

extension View {
    /// Scrolls when `scroll` is set; otherwise tapping or dragging selects a time.
    @ViewBuilder
    func chartXInteraction(scroll: ChartScroll?, selection: Binding<Date?>) -> some View {
        if let scroll {
            chartScrollableAxes(.horizontal)
                .chartXVisibleDomain(length: scroll.visibleLength)
                .chartScrollPosition(x: scroll.position)
        } else {
            chartXSelection(value: selection)
        }
    }
}
