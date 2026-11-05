import Foundation

/// `shifted` is printed as strongly as `base` and also follows Shift. `hint` is a small grey character
/// that is only reached by swiping up, as on the keys of the smaller iPads.
public struct TabletKey: Equatable, Sendable {
    public let base: String
    public let shifted: String?
    public let hint: String?
    public init(_ base: String, shifted: String? = nil, hint: String? = nil) {
        self.base = base
        self.shifted = shifted
        self.hint = hint
    }
    /// What swiping up inserts.
    public var upper: String? { hint ?? shifted }
}

/// The full-size layout of the 12.9- and 13-inch iPads: a number row and each language's punctuation keys,
/// taken from the native keyboards.
public struct TabletKeyboardLayout: Equatable, Sendable {
    public let numbers: [TabletKey]
    public let top: [TabletKey]
    public let home: [TabletKey]
    public let bottom: [TabletKey]
    /// ISO keyboards have an extra key beside the left Shift and an L-shaped Return.
    public var isISO: Bool { bottom.count == 11 }
    /// Natively, the number row of these layouts is lower than the other rows, and the bottom row differs.
    public let hasLowNumberRow: Bool

    public static func layout(for language: FlypeLanguage, usesEuro: Bool = regionUsesEuro) -> TabletKeyboardLayout {
        let rows = language.keyboardRows.map { row in row.map { TabletKey(String($0)) } }
        switch language {
        case .de:
            return .init(
                numbers: pairs("^°", "1!", "2\"", "3§", "4€", "5%", "6&", "7/", "8(", "9)", "0=", "ß?", "´`"),
                top: rows[0] + pairs("+*"), home: rows[1] + pairs("#'"),
                bottom: pairs("<>") + rows[2] + pairs(",;", ".:", "-_"), hasLowNumberRow: false)
        case .fr:
            return .init(
                numbers: pairs("@#", "&1", "é2", "\"3", "'4", "(5", "§6", "è7", "!8", "ç9", "à0", ")°", "-_"),
                top: rows[0] + pairs("^¨", "€*"), home: rows[1] + pairs("ù%", "`£"),
                bottom: pairs("<>") + rows[2] + pairs(",?", ";.", ":/", "=+"), hasLowNumberRow: false)
        case .es:
            return .init(
                numbers: pairs("ºª", "1!", "2\"", "3·", "4€", "5%", "6&", "7/", "8(", "9)", "0=", "'?", "¡¿"),
                top: rows[0] + pairs("`^", "+*"), home: rows[1] + pairs("´¨") + [TabletKey("ç")],
                bottom: pairs("<>") + rows[2] + pairs(",;", ".:", "-_"), hasLowNumberRow: true)
        case .it:
            return .init(
                numbers: pairs("\\|", "1!", "2\"", "3€", "4$", "5%", "6&", "7/", "8(", "9)", "0=", "'?", "ì^"),
                top: rows[0] + pairs("èé", "+*"), home: rows[1] + pairs("òç", "à°", "ù§"),
                bottom: pairs("<>") + rows[2] + pairs(",;", ".:", "-_"), hasLowNumberRow: false)
        case .en:
            let four = usesEuro ? "4€" : "4$"
            return .init(
                numbers: pairs("`~", "1!", "2@", "3#", four, "5%", "6^", "7&", "8*", "9(", "0)", "-_", "=+"),
                top: rows[0] + pairs("[{", "]}", "\\|"), home: rows[1] + pairs(";:", "'\""),
                bottom: rows[2] + pairs(",<", ".>", "/?"), hasLowNumberRow: true)
        case .nl:
            return .init(
                numbers: pairs("§±", "1!", "2@", "3#", "4€", "5%", "6^", "7&", "8*", "9(", "0)", "-_", "=+"),
                top: rows[0] + pairs("[{", "]}"), home: rows[1] + pairs(";:", "'\"", "\\|"),
                bottom: pairs("`~") + rows[2] + pairs(",<", ".>", "/?"), hasLowNumberRow: true)
        }
    }

    /// One page holds every symbol, so the large iPads need no second symbol page.
    public static let symbols: [[String]] = [
        ["`", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "<", ">"],
        ["[", "]", "{", "}", "#", "%", "^", "*", "+", "=", "\\", "|"],
        ["-", "/", ":", ";", "(", ")", "€", "&", "@", "£", "¥", "~"],
        ["…", ".", ",", "?", "!", "'", "\"", "_", "$"],
    ]

    public static var regionUsesEuro: Bool { Locale.current.currency?.identifier == "EUR" }

    fileprivate static func pairs(_ values: String...) -> [TabletKey] {
        values.map { TabletKey(String($0.first!), shifted: String($0.last!)) }
    }
}

/// The four-row layout of every smaller iPad. Key widths are measured on a row 830 units wide.
public struct CompactTabletLayout: Equatable, Sendable {
    public struct Widths: Equatable, Sendable {
        public let key, tab, caps, shift: Double
    }
    public let top: [TabletKey]
    public let home: [TabletKey]
    public let bottom: [TabletKey]
    public let symbolTop: [TabletKey]
    public let symbolHome: [TabletKey]
    public let symbolBottom: [TabletKey]
    public let widths: Widths

    public static func layout(for language: FlypeLanguage, usesEuro: Bool = TabletKeyboardLayout.regionUsesEuro)
        -> CompactTabletLayout
    {
        let rows = language.keyboardRows
        let digits = "1234567890".map { TabletKey(String($0)) }
        let currency = usesEuro ? "€" : "$"
        switch language {
        case .de:
            return .init(
                top: hinted(rows[0], "1234567890+"), home: hinted(rows[1], "\"§€%&/()='#"),
                bottom: hinted(rows[2], "—`´…@;:") + TabletKeyboardLayout.pairs(",!", ".?") + hinted("ß", "-"),
                symbolTop: digits + hinted("+", "*"), symbolHome: hinted("\"§€%&/()='#", "$£¥¿–\\[]{}|"),
                symbolBottom: hinted("—`´…@;:", "¡<>≠•^~") + TabletKeyboardLayout.pairs(",!", ".?") + hinted("-", "_"),
                widths: .init(key: 51, tab: 50, caps: 69, shift: 96))
        case .fr:
            return .init(
                top: hinted(rows[0], "1234567890"), home: hinted(rows[1], "@#&\"€(!)-*"),
                bottom: hinted(rows[2], "%_+=/;") + TabletKeyboardLayout.pairs(",?", ".!", ";:"),
                symbolTop: digits, symbolHome: hinted("@#&\"€(!)-*", "~°[]{}^$£¥"),
                symbolBottom: hinted("%_+=/;:", "§<>|\\…•") + TabletKeyboardLayout.pairs(",?", ".'"),
                widths: .init(key: 56.8, tab: 56, caps: 77, shift: 123))
        case .es:
            return .init(
                top: hinted(rows[0], "1234567890"), home: hinted(rows[1], "@#€&*()'\"+"),
                bottom: hinted(rows[2], "%_-=/;:") + TabletKeyboardLayout.pairs(",!", ".?"),
                symbolTop: digits, symbolHome: hinted("@#€&*()'\"+", "$£¥^[]{}ºª"),
                symbolBottom: hinted("%_-=/;:", "§|~¶\\<>") + TabletKeyboardLayout.pairs(",!", ".?"),
                widths: .init(key: 58, tab: 58, caps: 75, shift: 109))
        case .en, .it, .nl:
            return .init(
                top: hinted(rows[0], "1234567890"), home: hinted(rows[1], "@#\(currency)&*()'\""),
                bottom: hinted(rows[2], "%-+=/;:") + TabletKeyboardLayout.pairs(",!", ".?"),
                symbolTop: digits, symbolHome: hinted("@#\(currency)&*()'\"", "$£¥_^[]{}"),
                symbolBottom: hinted("%-+=/;:", "§|~…\\<>") + TabletKeyboardLayout.pairs(",!", ".?"),
                widths: .init(key: 56.3, tab: 73, caps: 93, shift: 123))
        }
    }

    private static func hinted(_ bases: String, _ hints: String) -> [TabletKey] {
        zip(bases, hints).map { TabletKey(String($0), hint: String($1)) }
    }
}
