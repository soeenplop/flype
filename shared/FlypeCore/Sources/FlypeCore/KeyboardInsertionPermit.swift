import Darwin
import Foundation

/// Per-recording permission, persisted across extension recreation during activation.
public struct KeyboardInsertionPermit: Codable, Equatable, Sendable {
    public let requestID: UUID
    public let createdAt: Date
    private var documentID: UUID
    public private(set) var awaitingReturn: Bool
    public private(set) var invalidated = false
    private var returnCandidate: UUID?
    private var candidateSince: TimeInterval?
    public init(requestID: UUID, documentID: UUID, awaitingReturn: Bool, createdAt: Date = Date()) {
        self.requestID = requestID
        self.documentID = documentID
        self.awaitingReturn = awaitingReturn
        self.createdAt = createdAt
    }
    public mutating func observe(
        documentID: UUID, activeRequestID: UUID?, completedRequestID: UUID? = nil,
        now: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        guard !invalidated else { return }
        if awaitingReturn {
            // A fast recognizer may finish before the first visible keyboard refresh.
            guard activeRequestID == requestID || completedRequestID == requestID else { return }
            // Wait for the proxy to settle after returning; its initial UUID can be transient.
            guard returnCandidate == documentID, let since = candidateSince else {
                returnCandidate = documentID
                candidateSince = now
                return
            }
            guard now - since >= 0.2 else { return }
            self.documentID = documentID
            awaitingReturn = false
            returnCandidate = nil
            candidateSince = nil
        } else if self.documentID != documentID {
            invalidated = true
        }
    }
    public mutating func resetTransientObservation() {
        returnCandidate = nil
        candidateSince = nil
    }
    public func isValid(at now: Date = Date()) -> Bool {
        let age = now.timeIntervalSince(createdAt)
        return age >= 0 && age < 600
    }
    public func allows(requestID: UUID?, documentID: UUID?, at now: Date = Date()) -> Bool {
        isValid(at: now) && !invalidated && !awaitingReturn && requestID == self.requestID
            && documentID == self.documentID
    }
}

public final class KeyboardInsertionPermitStore: @unchecked Sendable {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    public static func shared() throws -> KeyboardInsertionPermitStore {
        guard let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: ResultStore.appGroup)
        else {
            throw ResultStore.StoreError.unavailable
        }
        return KeyboardInsertionPermitStore(directory: group.appendingPathComponent("Insertion", isDirectory: true))
    }
    private var payload: URL { directory.appendingPathComponent("permit.json") }
    public func save(_ permit: KeyboardInsertionPermit) throws {
        try locked {
            #if os(iOS)
                try JSONEncoder().encode(permit).write(to: payload, options: [.atomic, .completeFileProtection])
            #else
                try JSONEncoder().encode(permit).write(to: payload, options: .atomic)
            #endif
        }
    }
    public func load(now: Date = Date()) throws -> KeyboardInsertionPermit? {
        try locked {
            let data: Data
            do { data = try Data(contentsOf: payload) } catch let error as CocoaError
                where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile
            { return nil }
            guard data.count < 16_384 else { throw ResultStore.StoreError.invalidResult }
            var permit = try JSONDecoder().decode(KeyboardInsertionPermit.self, from: data)
            guard permit.isValid(at: now) else {
                try FileManager.default.removeItem(at: payload)
                return nil
            }
            permit.resetTransientObservation()
            return permit
        }
    }
    public func clear(requestID: UUID) throws {
        try locked {
            guard let data = try? Data(contentsOf: payload), data.count < 16_384,
                let permit = try? JSONDecoder().decode(KeyboardInsertionPermit.self, from: data),
                permit.requestID == requestID
            else { return }
            try FileManager.default.removeItem(at: payload)
        }
    }
    private func locked<T>(_ action: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fd = open(directory.appendingPathComponent("permit.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw ResultStore.StoreError.unavailable }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw ResultStore.StoreError.unavailable }
        defer { flock(fd, LOCK_UN) }
        return try action()
    }
}
