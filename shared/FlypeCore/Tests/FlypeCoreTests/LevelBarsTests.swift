import XCTest

@testable import FlypeCore

final class LevelBarsTests: XCTestCase {
    func testSilenceAndInvalidLevelsKeepEveryBarLowAndStill() {
        for level in [0.0, -1, Double.nan, Double.infinity * -1] {
            for time in [0.0, 0.3, 1.7] {
                XCTAssertEqual(LevelBars.scales(level: level, time: time), Array(repeating: LevelBars.floor, count: 7))
            }
        }
    }

    func testLoudLevelRipplesWithinBounds() {
        let scales = LevelBars.scales(level: 1, time: 0.45)
        XCTAssertEqual(scales.count, LevelBars.count)
        XCTAssertTrue(scales.allSatisfy { $0 >= LevelBars.floor && $0 <= 1 })
        // The bars are out of step with each other, so the meter ripples.
        XCTAssertGreaterThan(scales.max()! - scales.min()!, 0.3)
        XCTAssertEqual(scales[0], 1, accuracy: 0.0001)
    }

    func testHigherLevelNeverLowersABar() {
        let quiet = LevelBars.scales(level: 0.3, time: 1.2)
        let loud = LevelBars.scales(level: 0.8, time: 1.2)
        for (a, b) in zip(quiet, loud) { XCTAssertLessThanOrEqual(a, b) }
    }

    func testSmoothingRisesFasterThanItFalls() {
        let up = LevelBars.smoothed(0, toward: 1, elapsed: 1.0 / 60)
        let down = 1 - LevelBars.smoothed(1, toward: 0, elapsed: 1.0 / 60)
        XCTAssertGreaterThan(up, down)
        XCTAssertEqual(LevelBars.smoothed(0.4, toward: .nan, elapsed: 10), 0, accuracy: 0.0001)
        XCTAssertEqual(LevelBars.smoothed(0.4, toward: 0.9, elapsed: 0), 0.4)
    }
}
