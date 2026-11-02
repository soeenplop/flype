import Foundation

/// Cursor-relative word boundaries. Character counts are for document-proxy
/// deletion; NSRange conversion for UITextChecker stays inside the keyboard.
public struct WordSuggestionContext: Equatable, Sendable {
    public let before: String
    public let after: String
    public let prefix: String
    public let suffix: String
    public var word: String { prefix + suffix }
    public var replacementCount: Int { prefix.count + suffix.count }
    public var precedingWord: String {
        let previous = before.dropLast(prefix.count)
        return String(previous.split(whereSeparator: { !Self.isWordCharacter($0) }).last ?? "").lowercased()
    }
    public init(before: String, after: String) {
        self.before = before
        self.after = after
        prefix = String(before.reversed().prefix(while: Self.isWordCharacter).reversed())
        suffix = String(after.prefix(while: Self.isWordCharacter))
    }
    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character == "'" || character == "’"
    }
}
