import Foundation

public enum DocumentIdentifier {
    /// UIKit declares a nonoptional UUID, but a keyboard proxy can return nil
    /// before its host document is attached. Read the public Objective-C getter
    /// as nullable, before Swift's nonoptional UUID bridge can trap.
    public static func read(from proxy: NSObject) -> UUID? {
        let getter = NSSelectorFromString("documentIdentifier")
        guard proxy.responds(to: getter),
            let value = proxy.perform(getter)?.takeUnretainedValue() as? NSUUID
        else { return nil }
        return value as UUID
    }
}
