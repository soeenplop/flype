import UIKit

/// Shared by UIKit keys and the SwiftUI microphone so their surfaces stay equal.
enum KeyboardKeyAppearance {
    static let accent = UIColor {
        $0.userInterfaceStyle == .dark
            ? UIColor(red: 0.75, green: 0.65, blue: 0.92, alpha: 1)
            : UIColor(red: 0.41, green: 0.28, blue: 0.64, alpha: 1)
    }
    static let cornerRadius: CGFloat = 7
    static let characterSurface = UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 0.262, alpha: 1) : .white
    }
    static let functionSurface = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.17, alpha: 1) : UIColor(red: 0.67, green: 0.69, blue: 0.72, alpha: 1)
    }
    static let pressedSurface = UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 0.38, alpha: 1) : UIColor(white: 0.76, alpha: 1)
    }
    static let foreground = UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 0.92, alpha: 1) : .black
    }
}
