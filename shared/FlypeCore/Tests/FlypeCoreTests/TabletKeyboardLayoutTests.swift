import XCTest

@testable import FlypeCore

final class TabletKeyboardLayoutTests: XCTestCase {
    func testEveryLanguageFillsTheSameGrid() {
        for language in FlypeLanguage.allCases {
            let layout = TabletKeyboardLayout.layout(for: language)
            XCTAssertEqual(layout.numbers.count, 13, "\(language)")
            XCTAssertEqual(layout.top.count, layout.isISO ? 12 : 13, "\(language)")
            XCTAssertEqual(layout.home.count, layout.isISO ? 12 : 11, "\(language)")
            XCTAssertEqual(layout.bottom.count, layout.isISO ? 11 : 10, "\(language)")
        }
    }

    func testLettersKeepTheirLanguageOrderAndHaveOneCharacter() {
        for language in FlypeLanguage.allCases {
            let layout = TabletKeyboardLayout.layout(for: language)
            let letters = [layout.top, layout.home, layout.bottom].map { row in
                row.filter { $0.shifted == nil }.map(\.base).joined()
            }
            XCTAssertEqual(letters, language.keyboardRows, "\(language)")
        }
    }

    func testGermanMatchesTheNativeKeyboard() {
        let layout = TabletKeyboardLayout.layout(for: .de)
        XCTAssertTrue(layout.isISO)
        XCTAssertEqual(layout.numbers[1], TabletKey("1", shifted: "!"))
        XCTAssertEqual(layout.numbers[4], TabletKey("4", shifted: "€"))
        XCTAssertEqual(layout.numbers[11], TabletKey("ß", shifted: "?"))
        XCTAssertEqual(layout.top.last, TabletKey("+", shifted: "*"))
        XCTAssertEqual(layout.home.last, TabletKey("#", shifted: "'"))
        XCTAssertEqual(layout.bottom.first, TabletKey("<", shifted: ">"))
    }

    func testSymbolsFitTheGridWithoutRepeats() {
        XCTAssertEqual(TabletKeyboardLayout.symbols.map(\.count), [13, 12, 12, 9])
        let all = TabletKeyboardLayout.symbols.flatMap { $0 }
        XCTAssertEqual(Set(all).count, all.count)
    }
}
