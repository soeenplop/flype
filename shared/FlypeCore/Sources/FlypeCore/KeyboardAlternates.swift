import Foundation

/// Ordered outward from the held key, with the base character added by the UI.
public enum KeyboardAlternates {
    public static func values(for character: String) -> [String]? {
        [
            "a": ["ä", "à", "á", "â", "ã", "å", "ā", "æ"],
            "e": ["é", "è", "ê", "ë", "ē", "ė", "ę"],
            "i": ["î", "ï", "í", "ī", "į", "ì"],
            "o": ["ô", "ò", "ó", "õ", "ö", "œ", "ø", "ō"],
            "u": ["ü", "û", "ù", "ú", "ū"],
            "s": ["ß", "ś", "š"], "c": ["ç", "ć", "č"],
            "n": ["ñ", "ń"], "y": ["ÿ"], "z": ["ž", "ź", "ż"],
            "l": ["ł"], "ä": ["æ"], "ö": ["ø", "œ"], "ü": ["û", "ù", "ú", "ū"],
            "-": ["–", "—", "•"], "/": ["\\"], "€": ["$", "£", "¥", "₩", "₽", "¢"],
            "\"": ["„", "“", "”", "«", "»"], "'": ["‚", "‘", "’", "‹", "›"],
            ".": ["…"], "?": ["¿"], "!": ["¡"], "%": ["‰"],
        ][character]
    }

    /// Horizontal dragging remains active below the strip, over the original key.
    /// Moving well outside the strip/key area cancels instead of inserting a letter.
    public static func selection(
        x: Double, y: Double, width: Double, height: Double,
        keyBottom: Double, count: Int
    ) -> Int? {
        guard count > 0, width > 0, x.isFinite, y.isFinite,
            x >= -24, x <= width + 24, y >= -36, y <= max(height, keyBottom) + 36
        else { return nil }
        return min(count - 1, max(0, Int(floor(x / (width / Double(count))))))
    }
}
