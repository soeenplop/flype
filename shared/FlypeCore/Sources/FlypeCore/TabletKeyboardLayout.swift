import Foundation

/// A key that shows two characters inserts `base`, and `shifted` while Shift is held down on purpose.
public struct TabletKey: Equatable, Sendable {
    public let base: String
    public let shifted: String?
    public init(_ base: String, shifted: String? = nil) {
        self.base = base
        self.shifted = shifted
    }
}

/// The full-size iPad layout: a number row and the punctuation keys of each language's native keyboard.
public struct TabletKeyboardLayout: Equatable, Sendable {
    public let numbers: [TabletKey]
    public let top: [TabletKey]
    public let home: [TabletKey]
    public let bottom: [TabletKey]
    /// ISO keyboards have an extra key beside the left Shift and an L-shaped Return.
    public var isISO: Bool { bottom.count == 11 }

    public static func layout(for language: FlypeLanguage) -> TabletKeyboardLayout {
        let rows = language.keyboardRows.map { row in row.map { TabletKey(String($0)) } }
        switch language {
        case .de:
            return .init(
                numbers: pairs("^°", "1!", "2\"", "3§", "4€", "5%", "6&", "7/", "8(", "9)", "0=", "ß?", "´`"),
                top: rows[0] + pairs("+*"), home: rows[1] + pairs("#'"),
                bottom: pairs("<>") + rows[2] + pairs(",;", ".:", "-_"))
        case .fr:
            return .init(
                numbers: pairs("@#", "&1", "é2", "\"3", "'4", "(5", "§6", "è7", "!8", "ç9", "à0", ")°", "-_"),
                top: rows[0] + pairs("^¨", "$*"), home: rows[1] + pairs("ù%", "`£"),
                bottom: pairs("<>") + rows[2] + pairs(",?", ";.", ":/", "=+"))
        case .es:
            return .init(
                numbers: pairs("ºª", "1!", "2\"", "3·", "4$", "5%", "6&", "7/", "8(", "9)", "0=", "'?", "¡¿"),
                top: rows[0] + pairs("`^", "+*"), home: rows[1] + pairs("´¨", "çÇ"),
                bottom: pairs("<>") + rows[2] + pairs(",;", ".:", "-_"))
        case .it:
            return .init(
                numbers: pairs("\\|", "1!", "2\"", "3£", "4$", "5%", "6&", "7/", "8(", "9)", "0=", "'?", "ì^"),
                top: rows[0] + pairs("èé", "+*"), home: rows[1] + pairs("òç", "à°", "ù§"),
                bottom: pairs("<>") + rows[2] + pairs(",;", ".:", "-_"))
        case .en, .nl:
            return .init(
                numbers: pairs("`~", "1!", "2@", "3#", "4$", "5%", "6^", "7&", "8*", "9(", "0)", "-_", "=+"),
                top: rows[0] + pairs("[{", "]}", "\\|"), home: rows[1] + pairs(";:", "'\""),
                bottom: rows[2] + pairs(",<", ".>", "/?"))
        }
    }

    /// One page holds every symbol, so the iPad needs no second symbol page.
    public static let symbols: [[String]] = [
        ["`", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "<", ">"],
        ["[", "]", "{", "}", "#", "%", "^", "*", "+", "=", "\\", "|"],
        ["-", "/", ":", ";", "(", ")", "€", "&", "@", "£", "¥", "~"],
        ["…", ".", ",", "?", "!", "'", "\"", "_", "$"],
    ]

    private static func pairs(_ values: String...) -> [TabletKey] {
        values.map { TabletKey(String($0.first!), shifted: String($0.last!)) }
    }
}
