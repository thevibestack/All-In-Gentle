import CoreGraphics
import Foundation
import SwiftUI
import XCTest

@testable import AllInGentleKit

/// Hermetic render + token tests for the dashboard chart widgets (spec
/// DW-1...DW-6). Pure logic is asserted directly; empty/1-sample rendering
/// goes through `ImageRenderer` so the SwiftUI bodies actually evaluate
/// (no crash, no divide-by-zero).
@MainActor
final class DashboardWidgetTests: XCTestCase {
    // MARK: - 2.1 Render: empty & one-sample series, no crash (DW-1/5)

    func testLineChartRendersEmptyAndSingleSampleWithoutCrash() {
        XCTAssertNotNil(renderedImage(AGLineChart(samples: [])))
        XCTAssertNotNil(renderedImage(AGLineChart(samples: [sample(42)])))
    }

    func testMiniChartRendersEmptyAndSingleSampleWithoutCrash() {
        XCTAssertNotNil(renderedImage(AGMiniChart(samples: [])))
        XCTAssertNotNil(renderedImage(AGMiniChart(samples: [sample(7)])))
    }

    func testBarChartRendersEmptyAndSingleSampleWithoutCrash() {
        XCTAssertNotNil(renderedImage(AGBarChart(perCoreValues: [])))
        XCTAssertNotNil(renderedImage(AGBarChart(perCoreValues: [50])))
    }

    func testMemoryBarRendersEmptyAndSegmentsWithoutCrash() {
        XCTAssertNotNil(renderedImage(AGMemoryBar(segments: [])))
        XCTAssertNotNil(renderedImage(AGMemoryBar(segments: [MemorySegment(kind: .app, bytes: 8)])))
    }

    func testGaugeRendersEmptyAndValueWithoutCrash() {
        XCTAssertNotNil(renderedImage(AGGauge(value: nil)))
        XCTAssertNotNil(renderedImage(AGGauge(value: 50)))
    }

    func testNetworkChartRendersEmptyAndSingleSeriesWithoutCrash() {
        XCTAssertNotNil(renderedImage(AGNetworkChart(downSamples: [], upSamples: [])))
        XCTAssertNotNil(renderedImage(AGNetworkChart(downSamples: [sample(10)], upSamples: [sample(20)])))
    }

    // MARK: - 2.1 Shared Y-domain logic (empty state, no divide-by-zero)

    func testChartYDomainIsNilWhenSeriesIsEmpty() {
        XCTAssertNil(chartYDomain([]))
    }

    func testChartYDomainPadsSingleSample() {
        // A lone point must still produce a non-degenerate range so the chart
        // does not divide by zero.
        XCTAssertEqual(chartYDomain([sample(50)]), 45...55)
    }

    func testChartYDomainSpansSeriesExtremes() {
        XCTAssertEqual(chartYDomain([sample(0), sample(100)]), 0...100)
    }

    func testChartYDomainPadsIdenticalValues() {
        XCTAssertEqual(chartYDomain([sample(5), sample(5)]), 4...6)
    }

    // MARK: - 2.4 Bar chart logic (DW-2)

    func testBarChartIsHiddenWhenValuesAreEmpty() {
        XCTAssertFalse(barChartShowsBars([]))
        XCTAssertTrue(barChartShowsBars([1]))
    }

    func testBarChartHeightClampsToZeroThroughHundred() {
        XCTAssertEqual(barChartHeight(50), 50)
        XCTAssertEqual(barChartHeight(150), 100)
        XCTAssertEqual(barChartHeight(-10), 0)
        XCTAssertEqual(barChartHeight(0), 0)
    }

    // MARK: - 2.5 Memory bar logic (DW-3)

    func testMemoryFractionsAreProportionalToBytes() {
        let segments = [
            MemorySegment(kind: .app, bytes: 8),
            MemorySegment(kind: .cache, bytes: 2),
            MemorySegment(kind: .wired, bytes: 2),
            MemorySegment(kind: .compressed, bytes: 4),
        ]
        let fractions = memoryFractions(segments)
        XCTAssertEqual(fractions, [0.5, 0.125, 0.125, 0.25])
    }

    func testMemoryFractionsGuardAgainstZeroTotal() {
        let zeroed = [
            MemorySegment(kind: .app, bytes: 0),
            MemorySegment(kind: .cache, bytes: 0),
            MemorySegment(kind: .wired, bytes: 0),
        ]
        XCTAssertEqual(memoryFractions(zeroed), [0, 0, 0])
        XCTAssertEqual(memoryFractions([]), [])
    }

    // MARK: - 2.6 Gauge logic (DW-4)

    func testGaugeProgressNormalizesPercentToUnitInterval() {
        XCTAssertEqual(gaugeProgress(fromPercent: 50), 0.5)
        XCTAssertEqual(gaugeProgress(fromPercent: 100), 1)
    }

    func testGaugeProgressMapsNilToZero() {
        XCTAssertEqual(gaugeProgress(fromPercent: nil), 0)
    }

    func testGaugeProgressClampsOutOfRangeValues() {
        XCTAssertEqual(gaugeProgress(fromPercent: 150), 1)
        XCTAssertEqual(gaugeProgress(fromPercent: -10), 0)
    }

    // MARK: - 2.5 Network domain (DW-5, dual series)

    func testNetworkChartDomainCoversBothSeries() {
        XCTAssertEqual(chartYDomain([sample(10), sample(40)]), 10...40)
    }

    func testNetworkChartDomainIsNilWhenBothSeriesAreEmpty() {
        XCTAssertNil(chartYDomain([]))
    }

    // MARK: - 2.2 Token-only palette (DW-6)

    func testLineChartColorsResolveFromAGTokens() {
        let chart = AGLineChart(samples: [])
        assertColor(chart.lineColor, equalsToken: AGColors.accent)
    }

    func testLineChartAreaColorIsAccentAtReducedOpacity() {
        let light = NSAppearance(named: .aqua)!
        let area = sRGBComponents(AGLineChart(samples: []).areaColor, under: light)
        let accent = sRGBComponents(AGColors.accent, under: light)
        XCTAssertEqual(area.r, accent.r, accuracy: 0.01)
        XCTAssertEqual(area.g, accent.g, accuracy: 0.01)
        XCTAssertEqual(area.b, accent.b, accuracy: 0.01)
        XCTAssertEqual(area.a, 0.15, accuracy: 0.01)
    }

    func testMiniChartColorResolvesFromAGAccent() {
        assertColor(AGMiniChart(samples: []).lineColor, equalsToken: AGColors.accent)
    }

    func testBarChartColorResolvesFromAGStatusLive() {
        assertColor(AGBarChart(perCoreValues: []).barColor, equalsToken: AGColors.statusLive)
    }

    func testMemorySegmentColorsResolveFromAGTokens() {
        assertColor(memorySegmentColor(.app), equalsToken: AGColors.accent)
        assertColor(memorySegmentColor(.cache), equalsToken: AGColors.statusLive)
        assertColor(memorySegmentColor(.wired), equalsToken: AGColors.statusPlaceholder)
        assertColor(memorySegmentColor(.compressed), equalsToken: AGColors.statusDisabled)
    }

    func testGaugeColorResolvesFromAGAccent() {
        assertColor(AGGauge(value: nil).gaugeColor, equalsToken: AGColors.accent)
    }

    func testNetworkChartColorsResolveFromAGTokens() {
        let chart = AGNetworkChart(downSamples: [], upSamples: [])
        assertColor(chart.downColor, equalsToken: AGColors.statusLive)
        assertColor(chart.upColor, equalsToken: AGColors.statusPlaceholder)
    }

    // MARK: - Helpers

    private func sample(_ value: Double) -> MetricSample {
        MetricSample(value: value)
    }

    /// Evaluates a SwiftUI body into an offscreen image. `nil` means the body
    /// failed to produce any output (crash path).
    private func renderedImage<V: View>(_ view: V, size: CGSize = CGSize(width: 320, height: 140)) -> CGImage? {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 1
        return renderer.cgImage
    }

    /// Resolves a dynamic token to sRGB components under a fixed appearance.
    private func sRGBComponents(_ color: Color, under appearance: NSAppearance) -> (
        r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat
    ) {
        let previous = NSAppearance.current
        NSAppearance.current = appearance
        defer { NSAppearance.current = previous }
        let resolved = NSColor(color).usingColorSpace(.sRGB) ?? .white
        return (resolved.redComponent, resolved.greenComponent, resolved.blueComponent, resolved.alphaComponent)
    }

    /// Asserts a widget color is exactly an AGColors token (DW-6): any
    /// hardcoded color literal would fail the component comparison.
    private func assertColor(
        _ color: Color, equalsToken token: Color, file: StaticString = #filePath, line: UInt = #line
    ) {
        let light = NSAppearance(named: .aqua)!
        let subject = sRGBComponents(color, under: light)
        let expected = sRGBComponents(token, under: light)
        XCTAssertEqual(subject.r, expected.r, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(subject.g, expected.g, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(subject.b, expected.b, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(subject.a, expected.a, accuracy: 0.01, file: file, line: line)
    }
}
