import Combine
import FlypeCore
import Foundation

@MainActor
final class OnboardingState: ObservableObject {
    @Published var progress: OnboardingProgress { didSet { progress.save(to: defaults) } }
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        progress = .load(from: defaults)
    }
    func begin(restart: Bool = false) {
        if restart { progress.step = .welcome }
        progress.hasBeenPresented = true
    }
}
