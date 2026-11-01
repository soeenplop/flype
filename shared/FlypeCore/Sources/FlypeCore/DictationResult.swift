import Foundation

public struct DictationResult: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let text: String
    public let keyboardRequestID: UUID?
    public let createdAt: Date
    public let expiresAt: Date

    public init(text: String, now: Date = Date(), lifetime: TimeInterval = 600, keyboardRequestID: UUID? = nil) {
        self.id = UUID()
        self.keyboardRequestID = keyboardRequestID
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.createdAt = now
        self.expiresAt = now.addingTimeInterval(lifetime)
    }

    public func canAutoInsert(at now: Date = Date()) -> Bool {
        isValid(at: now) && keyboardRequestID != nil
            && now.timeIntervalSinceReferenceDate < createdAt.timeIntervalSinceReferenceDate + 120
    }

    public func isValid(at date: Date) -> Bool {
        // Compare scalar timestamps explicitly. The installed iOS debug build
        // crashed in the synthesized Date.>= operator before writing the handoff.
        let timestamp = date.timeIntervalSinceReferenceDate
        return !text.isEmpty
            && timestamp >= createdAt.timeIntervalSinceReferenceDate
            && timestamp < expiresAt.timeIntervalSinceReferenceDate
    }
}
