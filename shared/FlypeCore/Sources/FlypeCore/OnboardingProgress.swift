import Foundation

/// Stores setup acknowledgements only, never practice text or audio.
public struct OnboardingProgress: Codable, Equatable, Sendable {
    public enum Step: Int, Codable, CaseIterable, Sendable {
        case welcome, keyboard, fullAccess, microphone, practice, finish
    }
    public var schemaVersion = 1
    public var step: Step = .welcome
    public var hasBeenPresented = false
    public var completed = false
    public var keyboardAcknowledged = false
    public var fullAccessAcknowledged = false
    public var dictationTestSucceeded = false
    public init() {}
    public var shouldPresentAutomatically: Bool { !hasBeenPresented && !completed }

    @discardableResult
    public mutating func advance(microphoneGranted: Bool = false, skipOptional: Bool = false) -> Bool {
        switch step {
        case .welcome: step = .keyboard
        case .keyboard:
            guard keyboardAcknowledged else { return false }
            step = .fullAccess
        case .fullAccess:
            guard fullAccessAcknowledged || skipOptional else { return false }
            step = fullAccessAcknowledged ? .microphone : .practice
        case .microphone:
            guard microphoneGranted || skipOptional else { return false }
            step = .practice
        case .practice:
            guard dictationTestSucceeded || skipOptional else { return false }
            step = .finish
        case .finish: return false
        }
        return true
    }
    public mutating func goBack() {
        step = Step(rawValue: max(0, step.rawValue - 1)) ?? .welcome
    }
    @discardableResult
    public mutating func complete() -> Bool {
        guard step == .finish else { return false }
        completed = true
        hasBeenPresented = true
        return true
    }
    public static func confirmsPracticeInsertion(
        before: String, after: String, dictation: String,
        published: Bool, sawCurrentPublication: Bool
    ) -> Bool {
        let text = dictation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard published, sawCurrentPublication, !text.isEmpty, before != after else { return false }
        // Existing sample text or unrelated typing must not count as an inserted dictation.
        return after.components(separatedBy: text).count > before.components(separatedBy: text).count
    }

    /// Scalar timestamps avoid the synthesized Date comparison thunk that crashes on the device SDK/runtime pair.
    public static func keyboardWasSeen(_ seen: Date, since started: Date, now: Date = Date()) -> Bool {
        let timestamp = seen.timeIntervalSinceReferenceDate
        return timestamp >= started.timeIntervalSinceReferenceDate && timestamp <= now.timeIntervalSinceReferenceDate
    }

    public static func load(from defaults: UserDefaults) -> Self {
        guard let data = defaults.data(forKey: "flype.onboarding.progress"),
            let progress = try? JSONDecoder().decode(Self.self, from: data),
            progress.schemaVersion == 1
        else { return Self() }
        return progress
    }
    public func save(to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: "flype.onboarding.progress")
    }
}
