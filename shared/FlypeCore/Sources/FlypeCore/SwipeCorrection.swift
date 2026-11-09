import CoreGraphics
import Foundation

/// A swiped word someone is changing by hand. It stays in memory until the new word is finished.
public struct SwipeCorrection: Sendable {
    public let path: [CGPoint]
    public let layout: SwipeKeyLayout
    public let language: FlypeLanguage
    public let documentID: UUID
    public let swiped: String
    /// Extending the word, as with geht to geht's. The path then only covers its start.
    public let extendsSwipedWord: Bool
    /// The first letter is capital only because a sentence starts here.
    public let startsSentence: Bool
    public private(set) var typed: String

    public init(
        path: [CGPoint], layout: SwipeKeyLayout, language: FlypeLanguage, documentID: UUID, swiped: String,
        extendsSwipedWord: Bool, startsSentence: Bool
    ) {
        self.path = path
        self.layout = layout
        self.language = language
        self.documentID = documentID
        self.swiped = swiped
        self.extendsSwipedWord = extendsSwipedWord
        self.startsSentence = startsSentence
        typed = extendsSwipedWord ? swiped : ""
    }

    public mutating func append(_ text: String) { typed += text }

    /// Returns false once the deletion reaches text from before the correction.
    public mutating func deleteLast() -> Bool {
        guard !typed.isEmpty else { return false }
        typed.removeLast()
        return true
    }

    public static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character == "'" || character == "’"
    }

    /// The word to count, or nil if it is no word or no change.
    public var learnableWord: String? {
        guard typed.precomposedStringWithCanonicalMapping.lowercased() != swiped.lowercased() else { return nil }
        return WordLearning.learnable(typed, startsSentence: startsSentence)
    }
}
