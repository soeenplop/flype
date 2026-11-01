import XCTest

@testable import FlypeCore

final class DictationOptionsTests: XCTestCase {
    func testOptionsDefaultToLocalAppleAndCleaned() {
        let name = "FlypeTest-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(DictationOptions.current(defaults: defaults).provider, .parakeet)
        XCTAssertEqual(DictationOptions.current(defaults: defaults).mode, .cleaned)
        defaults.set("parakeet", forKey: "speechProvider")
        defaults.set("cleaned", forKey: "dictationMode")
        XCTAssertEqual(DictationOptions.current(defaults: defaults).provider, .parakeet)
        XCTAssertEqual(DictationOptions.current(defaults: defaults).mode, .cleaned)
    }
    func testCleanedDefaultMigrationPreservesSubsequentLiteralChoice() {
        let name = "FlypeTest-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("verbatim", forKey: "dictationMode")
        DictationMode.adoptCleanedDefault(defaults: defaults)
        XCTAssertEqual(DictationOptions.current(defaults: defaults).mode, .cleaned)
        defaults.set("verbatim", forKey: "dictationMode")
        DictationMode.adoptCleanedDefault(defaults: defaults)
        XCTAssertEqual(DictationOptions.current(defaults: defaults).mode, .verbatim)
    }
}
