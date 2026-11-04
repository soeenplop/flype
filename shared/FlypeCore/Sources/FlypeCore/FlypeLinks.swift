import Foundation

/// Public pages for the in-app links and the App Store Connect metadata.
/// The website exists in German and English; every other interface language opens the English page.
public enum FlypeLinks {
    private static let website = "https://soeenplop.github.io/flype/"

    public static func privacyPolicy(language: FlypeLanguage = .interface()) -> URL {
        page(language == .de ? "datenschutz.html" : "en/privacy.html")
    }

    public static func support(language: FlypeLanguage = .interface()) -> URL {
        page(language == .de ? "support.html" : "en/support.html")
    }

    private static func page(_ path: String) -> URL {
        URL(string: website + path)!
    }
}
