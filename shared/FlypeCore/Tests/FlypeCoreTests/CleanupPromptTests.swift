import Foundation
import XCTest

@testable import FlypeCore

final class CleanupPromptTests: XCTestCase {
    func testLocalAndCloudCleanupUseTheSamePrompt() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // FlypeCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // FlypeCore
            .deletingLastPathComponent()  // shared
            .deletingLastPathComponent()
        let handler = repository.appendingPathComponent("supabase/functions/cloud-cleanup/handler.mjs")
        let source = try String(contentsOf: handler, encoding: .utf8)
        let start = try XCTUnwrap(source.range(of: "return `"))
        let end = try XCTUnwrap(source.range(of: "`;\n}\n\nconst json"))
        let template = String(source[start.upperBound..<end.lowerBound])
        for language in FlypeLanguage.allCases {
            let wording = CleanupPrompt.wording(for: language)
            XCTAssertTrue(source.contains("name: '\(wording.name)'"), language.rawValue)
            XCTAssertTrue(source.contains(wording.examples), language.rawValue)
            let expected = template.replacingOccurrences(of: "${language.name}", with: wording.name)
                .replacingOccurrences(of: "${language.examples}", with: wording.examples)
            XCTAssertEqual(CleanupPrompt.instructions(language: language), expected, language.rawValue)
        }
    }
}
