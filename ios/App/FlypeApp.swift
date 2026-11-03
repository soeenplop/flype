import FlypeCore
import SwiftUI
import UIKit

private final class FlypeAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        ParakeetDownloader.shared.handleBackgroundEvents(completion: completionHandler)
    }
}

@main
struct FlypeApp: App {
    @UIApplicationDelegateAdaptor(FlypeAppDelegate.self) private var appDelegate
    init() {
        DictationMode.adoptCleanedDefault()
        SpeechProvider.adoptParakeetDefault()
    }

    var body: some Scene {
        WindowGroup {
            HomeView().buttonBorderShape(.roundedRectangle(radius: 12))
        }
    }
}
