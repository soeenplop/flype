import XCTest

@testable import FlypeCore

final class FlypeLanguageTests: XCTestCase {
    private func isolatedDefaults() -> (UserDefaults, String) {
        let name = "FlypeLanguageTests-" + UUID().uuidString
        return (UserDefaults(suiteName: name)!, name)
    }
    func testInterfaceFollowsDeviceButDictationStaysIndependent() {
        let (defaults, name) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(FlypeLanguage.interface(defaults: defaults, preferred: ["fr-CA"]), .fr)
        XCTAssertEqual(FlypeLanguage.recognition(defaults: defaults), .de)
        defaults.set("it", forKey: "interfaceLanguage")
        defaults.set("nl", forKey: "dictationLanguage")
        XCTAssertEqual(FlypeLanguage.interface(defaults: defaults, preferred: ["en-GB"]), .it)
        XCTAssertEqual(FlypeLanguage.recognition(defaults: defaults), .nl)
    }
    func testUnsupportedDeviceLanguageAndInvalidPreferencesHaveSafeDefaults() {
        let (defaults, name) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(FlypeLanguage.interface(defaults: defaults, preferred: ["ja-JP", "es-MX"]), .es)
        XCTAssertEqual(FlypeLanguage.interface(defaults: defaults, preferred: ["ja-JP"]), .en)
        defaults.set("broken", forKey: "dictationLanguage")
        XCTAssertEqual(FlypeLanguage.recognition(defaults: defaults), .de)
    }
    func testRecordingOptionsFreezeLanguageUntilNextDictation() {
        let (defaults, name) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("fr", forKey: "dictationLanguage")
        let recording = DictationOptions.current(defaults: defaults, languageDefaults: defaults)
        defaults.set("es", forKey: "dictationLanguage")
        XCTAssertEqual(recording.language.localeIdentifier, "fr-FR")
        XCTAssertEqual(DictationOptions.current(defaults: defaults, languageDefaults: defaults).language, .es)
    }
    func testNativeLetterLayoutsAndAllCatalogEntriesArePresent() {
        XCTAssertEqual(FlypeLanguage.allCases.count, 6)
        XCTAssertEqual(FlypeLanguage.de.keyboardRows[0], "qwertzuiopü")
        XCTAssertEqual(FlypeLanguage.fr.keyboardRows[0], "azertyuiop")
        XCTAssertTrue(FlypeLanguage.es.keyboardRows[1].contains("ñ"))
        for language in FlypeLanguage.allCases {
            XCTAssertEqual(language.keyboardRows.count, 3)
            XCTAssertEqual(language.startingWords.count, 3)
            for key in L10n.supportedKeys {
                XCTAssertFalse(L10n.text(key, language: language).isEmpty, "\(language): \(key)")
            }
            XCTAssertFalse(L10n.text("Deine Gedanken.\nDeine Worte.", language: language).isEmpty)
        }
        XCTAssertEqual(L10n.text("Deine Gedanken.\nDeine Worte.", language: .en), "Your thoughts.\nYour words.")
        XCTAssertEqual(L10n.text("Wörter", language: .fr), "Mots")
    }
}
