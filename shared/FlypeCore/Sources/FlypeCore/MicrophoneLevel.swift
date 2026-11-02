import Foundation

public enum MicrophoneLevel {
    /// Decibel scaling makes quiet speech visible without pegging every loud syllable.
    public static func normalized(rms: Double) -> Double {
        guard rms.isFinite, rms > 0 else { return 0 }
        let decibels = 20 * log10(max(rms, 0.00001))
        return min(1, max(0, (decibels + 55) / 45))
    }
}
