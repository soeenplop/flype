import Foundation

public enum KeyboardTypingRules {
    public enum Capitalization { case none, words, sentences, allCharacters }
    public static func shouldUppercase(before: String, mode: Capitalization) -> Bool {
        switch mode {
        case .none: return false
        case .allCharacters: return true
        case .words: return before.isEmpty || before.last?.isWhitespace == true
        case .sentences:
            if before.isEmpty || before.last == "\n" { return true }
            guard before.last?.isWhitespace == true else { return false }
            let trimmed = before.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty || trimmed.last.map { ".!?".contains($0) } == true
        }
    }
    public static func canReplaceDoubleSpace(before: String) -> Bool {
        guard before.last == " ", let previous = before.dropLast().last else { return false }
        return previous.isLetter || previous.isNumber
    }
}
