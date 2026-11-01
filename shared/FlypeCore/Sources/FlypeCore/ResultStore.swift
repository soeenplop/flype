import Darwin
import Foundation

/// Short-lived handoff, not a history. The stable lock file protects atomic replacements
/// across the app and keyboard processes; locking the result file itself would not.
public final class ResultStore: @unchecked Sendable {
    public static let appGroup = "group.one.binda.flype.shared"
    private let directory: URL

    public enum StoreError: LocalizedError {
        case unavailable, invalidResult, verificationFailed
        public var errorDescription: String? {
            switch self {
            case .unavailable: "Die Übergabe an die Tastatur ist nicht verfügbar. Prüfe App-Gruppe und vollen Zugriff."
            case .invalidResult: "Die Transkription ist leer oder bereits abgelaufen."
            case .verificationFailed:
                "Die Transkription konnte nicht lesbar für die Tastatur gespeichert werden. Bitte versuche es erneut."
            }
        }
    }

    public init(directory: URL) { self.directory = directory }

    public static func shared() throws -> ResultStore {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
            throw StoreError.unavailable
        }
        return ResultStore(directory: url.appendingPathComponent("Handoff", isDirectory: true))
    }

    public func publish(_ result: DictationResult, now: Date = Date()) throws {
        guard result.isValid(at: now) else { throw StoreError.invalidResult }
        try locked {
            try write(result)
            guard try read() == result else { throw StoreError.verificationFailed }
        }
    }

    public func pending(now: Date = Date()) throws -> DictationResult? {
        try locked {
            guard let result = try read() else { return nil }
            guard result.isValid(at: now) else {
                try removeResult()
                return nil
            }
            return result
        }
    }

    /// Claim before touching the host text field. A crash after claiming can lose the
    /// handoff, but cannot offer it twice. Insertion into another app is not transactional.
    public func claim(id: UUID, now: Date = Date()) throws -> DictationResult? {
        try locked {
            guard let result = try read() else { return nil }
            guard result.isValid(at: now) else {
                try removeResult()
                return nil
            }
            guard result.id == id else { return nil }
            try removeResult()
            return result
        }
    }

    public func clear() throws { try locked { try removeResult() } }

    private var resultURL: URL { directory.appendingPathComponent("pending.json") }

    private func read() throws -> DictationResult? {
        do {
            return try JSONDecoder().decode(DictationResult.self, from: Data(contentsOf: resultURL))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return nil
        }
    }

    private func write(_ result: DictationResult) throws {
        let data = try JSONEncoder().encode(result)
        #if os(iOS)
            try data.write(to: resultURL, options: [.atomic, .completeFileProtection])
        #else
            try data.write(to: resultURL, options: .atomic)
        #endif
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: resultURL.path)
    }

    private func removeResult() throws {
        do {
            try FileManager.default.removeItem(at: resultURL)
        } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
            return
        }
    }

    #if DEBUG
        public var diagnosticDirectory: URL { directory }
    #endif

    private func locked<T>(_ operation: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let fd = open(directory.appendingPathComponent("handoff.lock").path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { throw StoreError.unavailable }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw StoreError.unavailable }
        defer { flock(fd, LOCK_UN) }
        return try operation()
    }
}
