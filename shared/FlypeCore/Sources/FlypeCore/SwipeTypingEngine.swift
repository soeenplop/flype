import CoreGraphics
import Foundation

/// Loads word lists and decodes swipes away from the thread that delivers touches.
public actor SwipeTypingEngine {
    private let locate: @Sendable (FlypeLanguage) -> URL?
    private var loaded: (language: FlypeLanguage, list: CombinedWordList)?

    public init(locate: @escaping @Sendable (FlypeLanguage) -> URL?) { self.locate = locate }

    /// Maps the file instead of reading it, so only the part in use takes up memory. Safe to call repeatedly.
    @discardableResult
    public func prepare(_ language: FlypeLanguage) -> Bool {
        if loaded?.language == language { return true }
        loaded = nil
        guard let url = locate(language), let data = try? Data(contentsOf: url, options: .alwaysMapped) else {
            return false
        }
        loaded = (language, CombinedWordList(data: data))
        return true
    }

    public func candidates(
        path: [CGPoint], layout: SwipeKeyLayout, language: FlypeLanguage,
        previousWord: String?, casing: SwipeCasing, limit: Int = 3
    ) -> [String] {
        guard prepare(language), let list = loaded?.list else { return [] }
        return SwipeDecoder.candidates(
            path: path, layout: layout, list: list, previousWord: previousWord, casing: casing, limit: limit)
    }
}
