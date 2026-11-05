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

    func testLettersKeepTheirLanguageOrder() {
        for language in FlypeLanguage.allCases {
            let layout = TabletKeyboardLayout.layout(for: language)
            let letters = [layout.top, layout.home, layout.bottom].map { row in
                row.filter { $0.shifted == nil }.map(\.base).joined()
            }
            for (row, expected) in zip(letters, language.keyboardRows) {
                XCTAssertTrue(row.hasPrefix(expected), "\(language): \(row)")
            }
        }
    }

    func testDutchIsNotTheEnglishLayout() {
        let dutch = TabletKeyboardLayout.layout(for: .nl)
        XCTAssertTrue(dutch.isISO)
        XCTAssertEqual(dutch.numbers.first, TabletKey("§", shifted: "±"))
        XCTAssertEqual(dutch.bottom.first, TabletKey("`", shifted: "~"))
        XCTAssertFalse(TabletKeyboardLayout.layout(for: .en).isISO)
    }

    func testCurrencyFollowsTheRegionOnEnglishOnly() {
        XCTAssertEqual(TabletKeyboardLayout.layout(for: .en, usesEuro: true).numbers[4].shifted, "€")
        XCTAssertEqual(TabletKeyboardLayout.layout(for: .en, usesEuro: false).numbers[4].shifted, "$")
        XCTAssertEqual(TabletKeyboardLayout.layout(for: .nl, usesEuro: false).numbers[4].shifted, "€")
        XCTAssertEqual(CompactTabletLayout.layout(for: .en, usesEuro: false).home[2].hint, "$")
    }

    func testCompactLayoutKeepsLettersAndFillsEverySymbolRow() {
        for language in FlypeLanguage.allCases {
            let layout = CompactTabletLayout.layout(for: language)
            let hinted = [layout.top, layout.home].map { $0.map(\.base).joined() }
            XCTAssertEqual(hinted, Array(language.keyboardRows.prefix(2)), "\(language)")
            XCTAssertTrue(layout.bottom.map(\.base).joined().hasPrefix(language.keyboardRows[2]), "\(language)")
            XCTAssertEqual(layout.symbolHome.count, layout.home.count, "\(language)")
            XCTAssertEqual(layout.symbolBottom.count, layout.bottom.count, "\(language)")
            XCTAssertEqual(layout.symbolTop.count, layout.top.count, "\(language)")
            XCTAssertTrue((layout.top + layout.home + layout.bottom).allSatisfy { $0.upper != nil }, "\(language)")
        }
    }

    func testCompactGermanMatchesTheNativeKeyboard() {
        let layout = CompactTabletLayout.layout(for: .de)
        XCTAssertEqual(layout.top.first, TabletKey("q", hint: "1"))
        XCTAssertEqual(layout.top.last, TabletKey("ü", hint: "+"))
        XCTAssertEqual(layout.home[2], TabletKey("d", hint: "€"))
        XCTAssertEqual(layout.bottom[7], TabletKey(",", shifted: "!"))
        XCTAssertEqual(layout.bottom.last, TabletKey("ß", hint: "-"))
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
