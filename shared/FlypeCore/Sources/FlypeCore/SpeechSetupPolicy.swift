import Foundation

/// Decides whether a device can dictate or the app has to ask for a recognizer first.
public enum SpeechSetupPolicy {
    public enum Requirement: Equatable, Sendable {
        case checking, ready
        /// Apple recognition works here, so the download stays optional.
        case choice
        /// Parakeet is the only recognizer that can run on this device.
        case downloadRequired
    }

    public static func requirement(provider: SpeechProvider, parakeetInstalled: Bool, appleAvailable: Bool)
        -> Requirement
    {
        if parakeetInstalled { return .ready }
        guard appleAvailable else { return .downloadRequired }
        return provider == .apple ? .ready : .choice
    }
}

/// A persisted request may resume once per controller lifetime, never recursively after an error.
public struct DownloadResumePolicy: Sendable {
    private var attempted = false
    public init() {}
    public mutating func consume(pending: Bool) -> Bool {
        guard pending, !attempted else { return false }
        attempted = true
        return true
    }
    public mutating func beganDownload() { attempted = true }
}
