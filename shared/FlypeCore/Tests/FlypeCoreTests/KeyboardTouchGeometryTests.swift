import CoreGraphics
import XCTest

@testable import FlypeCore

final class KeyboardTouchGeometryTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)

    func testHorizontalGapsBelongToTheClosestKey() {
        let frames = [CGRect(x: 4, y: 0, width: 26, height: 40), CGRect(x: 36, y: 0, width: 26, height: 40)]
        XCTAssertEqual(KeyboardTouchGeometry.nearest(to: CGPoint(x: 32, y: 20), frames: frames, within: bounds), 0)
        XCTAssertEqual(KeyboardTouchGeometry.nearest(to: CGPoint(x: 34, y: 20), frames: frames, within: bounds), 1)
        XCTAssertEqual(KeyboardTouchGeometry.nearest(to: CGPoint(x: 1, y: 20), frames: frames, within: bounds), 0)
    }
    func testVerticalGapsSelectOneRowBeforeChoosingAKey() {
        let frames = [CGRect(x: 0, y: 0, width: 100, height: 40), CGRect(x: 0, y: 49, width: 100, height: 40)]
        XCTAssertEqual(KeyboardTouchGeometry.nearest(to: CGPoint(x: 55, y: 43), frames: frames, within: bounds), 0)
        XCTAssertEqual(KeyboardTouchGeometry.nearest(to: CGPoint(x: 55, y: 46), frames: frames, within: bounds), 1)
    }
    func testKeyCentersAndUnequalFunctionKeysArePreserved() {
        let frames = [CGRect(x: 0, y: 0, width: 14, height: 40), CGRect(x: 20, y: 0, width: 60, height: 40)]
        XCTAssertEqual(KeyboardTouchGeometry.nearest(to: CGPoint(x: 7, y: 20), frames: frames, within: bounds), 0)
        XCTAssertEqual(KeyboardTouchGeometry.nearest(to: CGPoint(x: 50, y: 20), frames: frames, within: bounds), 1)
    }
    func testTouchesOutsideKeyboardNeverBecomeLetters() {
        let frames = [CGRect(x: 0, y: 0, width: 100, height: 100)]
        for point in [CGPoint(x: -1, y: 20), CGPoint(x: 20, y: -1), CGPoint(x: 100, y: 20), CGPoint(x: 20, y: 100)] {
            XCTAssertNil(KeyboardTouchGeometry.nearest(to: point, frames: frames, within: bounds))
        }
    }
    func testOuterMarginsBelongToTheEndKeys() {
        let container = CGRect(x: 0, y: 0, width: 402, height: 262)
        let area = KeyboardTouchGeometry.touchArea(container: container, topLimit: 44)
        let frames = [CGRect(x: 6, y: 46, width: 30, height: 45), CGRect(x: 366, y: 46, width: 30, height: 45)]
        for x in [0, 1, 3, 5] {
            XCTAssertEqual(
                KeyboardTouchGeometry.nearest(to: CGPoint(x: CGFloat(x), y: 60), frames: frames, within: area), 0)
        }
        for x in [397, 399, 401] {
            XCTAssertEqual(
                KeyboardTouchGeometry.nearest(to: CGPoint(x: CGFloat(x), y: 60), frames: frames, within: area), 1)
        }
    }
    func testTouchAreaEndsAtTheBarAboveAndCoversTheBottomMargin() {
        let container = CGRect(x: 0, y: 0, width: 402, height: 262)
        let area = KeyboardTouchGeometry.touchArea(container: container, topLimit: 44)
        XCTAssertEqual(area, CGRect(x: 0, y: 44, width: 402, height: 218))
        let frames = [CGRect(x: 6, y: 46, width: 390, height: 211)]
        XCTAssertEqual(KeyboardTouchGeometry.nearest(to: CGPoint(x: 200, y: 45), frames: frames, within: area), 0)
        XCTAssertEqual(KeyboardTouchGeometry.nearest(to: CGPoint(x: 200, y: 260), frames: frames, within: area), 0)
        XCTAssertNil(KeyboardTouchGeometry.nearest(to: CGPoint(x: 200, y: 43), frames: frames, within: area))
    }
    func testTouchAreaWithoutABarIsTheWholeKeyboard() {
        let container = CGRect(x: 0, y: 0, width: 402, height: 216)
        XCTAssertEqual(KeyboardTouchGeometry.touchArea(container: container, topLimit: nil), container)
    }
    func testTouchAreaNeverHasNegativeHeight() {
        let container = CGRect(x: 0, y: 0, width: 402, height: 216)
        XCTAssertEqual(KeyboardTouchGeometry.touchArea(container: container, topLimit: 300).height, 0)
    }
    func testEmptyAndInvalidGeometryDoesNotCreateAKey() {
        XCTAssertNil(KeyboardTouchGeometry.nearest(to: .zero, frames: [], within: bounds))
        XCTAssertNil(KeyboardTouchGeometry.nearest(to: .zero, frames: [.zero, .null, .infinite], within: bounds))
        XCTAssertNil(KeyboardTouchGeometry.nearest(to: CGPoint(x: CGFloat.nan, y: 1), frames: [bounds], within: bounds))
    }
    func testEveryPixelAcrossTwoRowsAndKeyGapsHasExactlyOneTarget() {
        let frames = [
            CGRect(x: 3, y: 3, width: 41, height: 41), CGRect(x: 50, y: 3, width: 47, height: 41),
            CGRect(x: 3, y: 53, width: 41, height: 44), CGRect(x: 50, y: 53, width: 47, height: 44),
        ]
        for x in 0..<100 {
            for y in 0..<100 {
                XCTAssertNotNil(KeyboardTouchGeometry.nearest(to: CGPoint(x: x, y: y), frames: frames, within: bounds))
            }
        }
    }
}
