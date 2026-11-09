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
    /// As on the iPhone's own keyboard: an apostrophe always leads back to the letters, because a word continues.
    /// A space or return only does once something was typed here, so an empty one does not close the view just opened.
    public static func leavesSymbols(after key: String, typedInSymbols: Bool) -> Bool {
        if key == "'" { return true }
        return (key == " " || key == "\n") && typedInSymbols
    }
    public static func canReplaceDoubleSpace(before: String) -> Bool {
        guard before.last == " ", let previous = before.dropLast().last else { return false }
        return previous.isLetter || previous.isNumber
    }
}
