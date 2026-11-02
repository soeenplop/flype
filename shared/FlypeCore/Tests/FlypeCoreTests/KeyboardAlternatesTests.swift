import XCTest

@testable import FlypeCore

final class KeyboardAlternatesTests: XCTestCase {
    func testGermanCharactersAndPunctuationHaveAlternatives() {
        XCTAssertTrue(KeyboardAlternates.values(for: "a")!.contains("ä"))
        XCTAssertTrue(KeyboardAlternates.values(for: "o")!.contains("ö"))
        XCTAssertTrue(KeyboardAlternates.values(for: "u")!.contains("ü"))
        XCTAssertTrue(KeyboardAlternates.values(for: "s")!.contains("ß"))
        XCTAssertEqual(KeyboardAlternates.values(for: "."), ["…"])
        XCTAssertNil(KeyboardAlternates.values(for: "q"))
    }
    func testSlideBelowStripSelectsAcrossAllCells() {
        for index in 0..<9 {
            XCTAssertEqual(
                KeyboardAlternates.selection(
                    x: Double(index * 32 + 16), y: 80,
                    width: 288, height: 50, keyBottom: 96, count: 9), index)
        }
    }
    func testEdgesClampButDraggingAwayCancels() {
        func index(_ x: Double, _ y: Double) -> Int? {
            KeyboardAlternates.selection(x: x, y: y, width: 288, height: 50, keyBottom: 96, count: 9)
        }
        XCTAssertEqual(index(-10, 80), 0)
        XCTAssertEqual(index(300, 80), 8)
        XCTAssertNil(index(-30, 80))
        XCTAssertNil(index(320, 80))
        XCTAssertNil(index(100, 150))
        XCTAssertNil(index(100, -40))
        XCTAssertNil(index(.nan, 80))
    }
    func testAlternativesAreUniqueAndDoNotRepeatBase() {
        for character in Array("abcdefghijklmnopqrstuvwxyzäöü-/.?!%€\"'").map(String.init) {
            guard let values = KeyboardAlternates.values(for: character) else { continue }
            XCTAssertFalse(values.contains(character))
            XCTAssertEqual(Set(values).count, values.count)
        }
    }
}
