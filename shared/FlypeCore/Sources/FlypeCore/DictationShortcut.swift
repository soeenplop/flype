import Foundation

/// Holding the chosen key starts dictation; releasing finishes it. Combinations cancel it.
public struct DictationShortcut: Sendable {
    public enum Action: Equatable, Sendable { case armed, started, finished, cancelled }
    public static let holdDelay: TimeInterval = 0.14
    private var pressedAt: TimeInterval?
    private var wasDown = false
    private var blocked = false
    private var active = false
    public var isHeld: Bool { wasDown }
    public init() {}

    public mutating func interrupt() -> Action? {
        let action: Action? = active || pressedAt != nil ? .cancelled : nil
        active = false
        pressedAt = nil
        blocked = wasDown
        return action
    }
    public mutating func update(keyDown: Bool, otherModifier: Bool, now: TimeInterval) -> Action? {
        defer { wasDown = keyDown }
        if keyDown {
            if otherModifier {
                blocked = true
                return interrupt()
            }
            if !wasDown && !blocked {
                pressedAt = now
                return .armed
            }
            return nil
        }
        defer {
            active = false
            pressedAt = nil
            blocked = false
        }
        guard active else { return pressedAt != nil ? .cancelled : nil }
        return otherModifier || blocked ? .cancelled : .finished
    }
    /// Capture is armed on key-down; only confirmation waits to distinguish shortcuts from dictation.
    public mutating func advance(now: TimeInterval) -> Action? {
        guard wasDown, !blocked, !active, let pressedAt, now - pressedAt >= Self.holdDelay else { return nil }
        active = true
        return .started
    }
}
