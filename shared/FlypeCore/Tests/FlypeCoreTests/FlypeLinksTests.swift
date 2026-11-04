import XCTest

@testable import FlypeCore

final class FlypeLinksTests: XCTestCase {
    func testGermanInterfaceOpensTheGermanPages() {
        XCTAssertEqual(
            FlypeLinks.privacyPolicy(language: .de).absoluteString,
            "https://soeenplop.github.io/flype/datenschutz.html")
        XCTAssertEqual(
            FlypeLinks.support(language: .de).absoluteString, "https://soeenplop.github.io/flype/support.html")
    }

    func testEveryOtherInterfaceLanguageOpensTheEnglishPages() {
        for language in FlypeLanguage.allCases where language != .de {
            XCTAssertEqual(
                FlypeLinks.privacyPolicy(language: language).absoluteString,
                "https://soeenplop.github.io/flype/en/privacy.html")
            XCTAssertEqual(
                FlypeLinks.support(language: language).absoluteString,
                "https://soeenplop.github.io/flype/en/support.html")
        }
    }
}
