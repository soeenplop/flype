import Darwin
import Foundation

/// A short-lived, one-use capability. An arbitrary external flype:// URL must
/// never start microphone capture without a request issued by our keyboard.
public struct KeyboardStartRequest: Codable, Equatable, Sendable {
    public let id: UUID
    public let targetDocumentID: UUID?
    public let returnApplicationID: String?
    public let createdAt: Date
    public let expiresAt: Date

    public init(now: Date = Date(), targetDocumentID: UUID? = nil, returnApplicationID: String? = nil) {
        self.targetDocumentID = targetDocumentID
        self.returnApplicationID = returnApplicationID
        id = UUID()
        createdAt = now
        expiresAt = now.addingTimeInterval(30)
    }

    // Keep keyboard launches separate from old development installs and the legacy OAuth callback.
    public static let appURLScheme = "one.binda.flype"
    public static func acceptsAppURLScheme(_ scheme: String?) -> Bool {
        scheme == appURLScheme || scheme == "flype"
    }
    public var url: URL { URL(string: "\(Self.appURLScheme)://dictate?request=\(id.uuidString)")! }

    public func isValid(at now: Date) -> Bool {
        let time = now.timeIntervalSinceReferenceDate
        return time >= createdAt.timeIntervalSinceReferenceDate && time < expiresAt.timeIntervalSinceReferenceDate
    }

    public static func requestID(from url: URL) -> UUID? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            Self.acceptsAppURLScheme(components.scheme), components.host == "dictate",
            components.path.isEmpty, components.user == nil, components.password == nil,
            components.port == nil, components.fragment == nil,
            let items = components.queryItems, items.count == 1,
            items[0].name == "request", let value = items[0].value
        else { return nil }
        return UUID(uuidString: value)
    }
}

public final class KeyboardStartStore: @unchecked Sendable {
    private let directory: URL
    public init(directory: URL) { self.directory = directory }

    public static func shared() throws -> KeyboardStartStore {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: ResultStore.appGroup)
        else {
            throw ResultStore.StoreError.unavailable
        }
        return KeyboardStartStore(directory: url.appendingPathComponent("VoiceStart", isDirectory: true))
    }

    public func issue(_ request: KeyboardStartRequest) throws {
        try locked {
            let data = try JSONEncoder().encode(request)
            #if os(iOS)
                try data.write(to: payloadURL, options: [.atomic, .completeFileProtection])
            #else
                try data.write(to: payloadURL, options: .atomic)
            #endif
        }
    }

    public func consume(id: UUID, now: Date = Date()) throws -> Bool {
        try consumeRequest(id: id, now: now) != nil
    }

    public func consumeRequest(id: UUID, now: Date = Date()) throws -> KeyboardStartRequest? {
        try locked {
            let request: KeyboardStartRequest
            do {
                request = try JSONDecoder().decode(KeyboardStartRequest.self, from: Data(contentsOf: payloadURL))
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
                return nil
            }
            guard request.id == id else { return nil }
            try FileManager.default.removeItem(at: payloadURL)
            return request.isValid(at: now) ? request : nil
        }
    }

    private var payloadURL: URL { directory.appendingPathComponent("request.json") }
    private func locked<T>(_ action: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let descriptor = open(directory.appendingPathComponent("request.lock").path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { throw ResultStore.StoreError.unavailable }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw ResultStore.StoreError.unavailable }
        defer { flock(descriptor, LOCK_UN) }
        return try action()
    }
}
