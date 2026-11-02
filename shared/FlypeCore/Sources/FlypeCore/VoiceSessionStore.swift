import Darwin
import Foundation

public struct VoiceSessionState: Codable, Sendable {
    public enum Phase: String, Codable, Sendable { case ready, preparing, recording, processing }
    public let id: UUID
    public let phase: Phase
    public let dictationID: UUID?
    public let updatedAt: Date
    public let inputLevel: Double?
    public let recordingDuration: TimeInterval?
    public init(
        id: UUID, phase: Phase, dictationID: UUID?, now: Date = Date(), inputLevel: Double? = nil,
        recordingDuration: TimeInterval? = nil
    ) {
        self.inputLevel = inputLevel
        self.recordingDuration = recordingDuration
        self.id = id
        self.phase = phase
        self.dictationID = dictationID
        updatedAt = now
    }
    public func isAlive(at now: Date = Date()) -> Bool {
        let age = now.timeIntervalSince(updatedAt)
        return age >= 0 && age < 3
    }
}

public struct VoiceSessionCommand: Codable, Sendable {
    public enum Action: String, Codable, Sendable { case start, stop, end }
    public let sessionID: UUID
    public let requestID: UUID
    public let action: Action
    public let createdAt: Date
    public init(sessionID: UUID, requestID: UUID, action: Action, now: Date = Date()) {
        self.sessionID = sessionID
        self.requestID = requestID
        self.action = action
        createdAt = now
    }
}

/// Separate files prevent app status writes from overwriting keyboard commands.
/// A stable process lock serializes claiming, session shutdown and publication.
public final class VoiceSessionStore: @unchecked Sendable {
    private let directory: URL
    public init(directory: URL) { self.directory = directory }
    public static func shared() throws -> VoiceSessionStore {
        guard let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: ResultStore.appGroup)
        else {
            throw ResultStore.StoreError.unavailable
        }
        return VoiceSessionStore(directory: group.appendingPathComponent("VoiceSession", isDirectory: true))
    }
    public func publish(_ state: VoiceSessionState) throws { try locked { try write(state, name: "state") } }
    public func state(now: @autoclosure () -> Date = Date()) throws -> VoiceSessionState? {
        try locked {
            let value: VoiceSessionState? = try read("state")
            // Evaluate the clock after taking the lock: a publisher may have updated while we waited.
            return value?.isAlive(at: now()) == true ? value : nil
        }
    }
    public func send(_ command: VoiceSessionCommand, now: @autoclosure () -> Date = Date()) throws {
        try locked {
            let current: VoiceSessionState? = try read("state")
            let now = now()
            guard current?.id == command.sessionID, current?.isAlive(at: now) == true else {
                throw ResultStore.StoreError.unavailable
            }
            // Never replace an unprocessed button press with another press.
            let existing: VoiceSessionCommand? = try read("command")
            guard existing == nil || now.timeIntervalSince(existing!.createdAt) >= 5 else { return }
            try write(command, name: "command")
        }
    }
    public func claim(sessionID: UUID, now: @autoclosure () -> Date = Date()) throws -> VoiceSessionCommand? {
        try locked {
            guard let command: VoiceSessionCommand = try read("command") else { return nil }
            try remove("command")
            let age = now().timeIntervalSince(command.createdAt)
            guard command.sessionID == sessionID, age >= 0, age < 5 else { return nil }
            return command
        }
    }
    public func keyboardSeen(now: Date = Date()) throws { try locked { try write(now, name: "keyboard") } }
    public func lastKeyboardSeen() throws -> Date? { try locked { try read("keyboard") } }
    public func clear() throws {
        try locked {
            try remove("state")
            try remove("command")
            try remove("keyboard")
        }
    }
    private func url(_ name: String) -> URL { directory.appendingPathComponent(name + ".json") }
    private func read<T: Decodable>(_ name: String) throws -> T? {
        do { return try JSONDecoder().decode(T.self, from: Data(contentsOf: url(name))) } catch let e as CocoaError
            where e.code == .fileReadNoSuchFile || e.code == .fileNoSuchFile
        { return nil }
    }
    private func write<T: Encodable>(_ value: T, name: String) throws {
        let data = try JSONEncoder().encode(value)
        #if os(iOS)
            try data.write(to: url(name), options: [.atomic, .completeFileProtection])
        #else
            try data.write(to: url(name), options: .atomic)
        #endif
    }
    private func remove(_ name: String) throws {
        do { try FileManager.default.removeItem(at: url(name)) } catch let e as CocoaError
            where e.code == .fileReadNoSuchFile || e.code == .fileNoSuchFile
        {}
    }
    private func locked<T>(_ action: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fd = open(directory.appendingPathComponent("session.lock").path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { throw ResultStore.StoreError.unavailable }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw ResultStore.StoreError.unavailable }
        defer { flock(fd, LOCK_UN) }
        return try action()
    }
}

public enum VoiceSessionPolicy {
    public static func shouldEnd(isBusy: Bool, appIsActive: Bool, lastInteraction: Date, now: Date = Date()) -> Bool {
        !isBusy && !appIsActive && now.timeIntervalSince(lastInteraction) >= 300
    }
}
