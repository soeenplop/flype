import Foundation
import notify

/// Wakes the other process right away instead of waiting for its next poll.
/// A signal carries no data: the shared files stay the only source of truth, so a
/// signal from elsewhere only causes an extra read, and polling catches a missed one.
public enum SessionSignal: String, Sendable {
    /// The keyboard sent a command to the app.
    case command = "group.one.binda.flype.shared.command"
    /// The app changed the session phase or published a result.
    case state = "group.one.binda.flype.shared.state"

    public func post() { notify_post(rawValue) }

    /// Calls `handler` on the main thread until the observation is released.
    @MainActor
    public func observe(_ handler: @escaping @MainActor () -> Void) -> SessionSignalObservation? {
        var token: Int32 = 0
        let status = notify_register_dispatch(rawValue, &token, .main) { _ in
            MainActor.assumeIsolated { handler() }
        }
        return status == NOTIFY_STATUS_OK ? SessionSignalObservation(token: token) : nil
    }
}

public final class SessionSignalObservation {
    private let token: Int32
    init(token: Int32) { self.token = token }
    deinit { notify_cancel(token) }
}
