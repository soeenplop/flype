import Foundation

/// The text around the cursor, so a dictation can continue a sentence that was started by typing
/// and fit in front of text that follows.
public struct DictationFieldContext: Codable, Sendable {
    public static let maximumLength = 200
    public let requestID: UUID
    public let text: String
    /// Optional, so a context written by an older keyboard still reads.
    public let following: String?
    public let createdAt: Date
    public init(requestID: UUID, text: String, following: String = "", createdAt: Date = Date()) {
        self.requestID = requestID
        self.text = Self.tail(of: text)
        self.following = following.isEmpty ? nil : Self.head(of: following)
        self.createdAt = createdAt
    }
    public static func tail(of text: String) -> String { String(text.suffix(maximumLength)) }
    public static func head(of text: String) -> String { String(text.prefix(maximumLength)) }
    /// The space a dictation needs when the field ends right at a word or sentence.
    public static func separator(before text: String, after context: String?) -> String {
        guard let last = context?.last, let first = text.first, !last.isWhitespace, !first.isWhitespace,
            !"([{„«‹¿¡/-–@#".contains(last), !",.;:!?)]}»›…%".contains(first)
        else { return "" }
        return " "
    }
    /// The space after a dictation: always at the end of the field, and before following text only where a word starts.
    public static func trailingSeparator(after text: String, following: String?) -> String {
        guard let following, !following.isEmpty else { return " " }
        return separator(before: following, after: text)
    }
    public func isValid(at now: Date = Date()) -> Bool {
        let age = now.timeIntervalSince(createdAt)
        return age >= 0 && age < 600
    }
}

/// Hands the context from the keyboard to the app. It is deleted as soon as the app has read it.
public final class DictationFieldContextStore: @unchecked Sendable {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    public static func shared() throws -> DictationFieldContextStore {
        guard let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: ResultStore.appGroup)
        else { throw ResultStore.StoreError.unavailable }
        return DictationFieldContextStore(directory: group.appendingPathComponent("FieldContext", isDirectory: true))
    }
    private var payload: URL { directory.appendingPathComponent("context.json") }
    public func save(_ context: DictationFieldContext) throws {
        guard !context.text.isEmpty || context.following != nil else { return clear() }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #if os(iOS)
            try JSONEncoder().encode(context).write(to: payload, options: [.atomic, .completeFileProtection])
        #else
            try JSONEncoder().encode(context).write(to: payload, options: .atomic)
        #endif
    }
    /// Returns the context only for the matching dictation, and always leaves nothing behind.
    public func take(requestID: UUID, now: Date = Date()) -> DictationFieldContext? {
        defer { clear() }
        guard let data = try? Data(contentsOf: payload), data.count < 16_384,
            let context = try? JSONDecoder().decode(DictationFieldContext.self, from: data),
            context.requestID == requestID, context.isValid(at: now)
        else { return nil }
        return context
    }
    public func clear() { try? FileManager.default.removeItem(at: payload) }
}
