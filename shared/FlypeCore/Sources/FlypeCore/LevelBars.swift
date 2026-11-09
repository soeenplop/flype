import Foundation

/// Bar heights for the recording meter: seven bars that ripple from left to right.
/// The ripple only grows with the input level, so silence leaves low, still bars.
public enum LevelBars {
    public static let count = 7
    /// Height of a silent bar, relative to the tallest possible bar.
    public static let floor = 0.2
    /// One ripple cycle and the delay between neighboring bars, in seconds.
    static let period = 0.9
    static let stagger = 0.15

    /// Relative heights in `floor...1`, one per bar.
    public static func scales(level: Double, time: TimeInterval) -> [Double] {
        let level = level.isFinite ? min(1, max(0, level)) : 0
        let time = time.isFinite ? time : 0
        return (0..<count).map { index in
            let phase = (time - Double(index) * stagger) / period
            // Like the design: each bar moves between 35 % and full height.
            let wave = 0.35 + 0.65 * (0.5 - 0.5 * cos(2 * .pi * phase))
            return floor + (1 - floor) * level * wave
        }
    }

    /// Moves a displayed level toward a new sample: fast up, slower down.
    public static func smoothed(_ current: Double, toward target: Double, elapsed: TimeInterval) -> Double {
        let target = target.isFinite ? min(1, max(0, target)) : 0
        let current = current.isFinite ? min(1, max(0, current)) : 0
        let rate = target > current ? 30.0 : 8.0
        let step = 1 - exp(-rate * max(0, elapsed.isFinite ? elapsed : 0))
        return current + (target - current) * step
    }
}
