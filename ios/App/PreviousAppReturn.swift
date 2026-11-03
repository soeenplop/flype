#if DEBUG
    import UIKit
    import ObjectiveC.runtime

    /// Development-only experiment. UISystemNavigationAction is not public API.
    /// Release builds contain none of this code. Never suspend/terminate the app
    /// to fake a return, and never guess the destination using an unrelated URL.
    @MainActor
    final class PreviousAppReturn {
        static let shared = PreviousAppReturn()
        private var requestID: UUID?
        private var capturedAt = Date.distantPast
        private var action: NSObject?
        private var applicationID: String?

        func capture(for requestID: UUID, applicationID: String?) {
            self.requestID = requestID
            self.applicationID = applicationID
            capturedAt = Date()
            action = findAction()
            print("FLYPE_RETURN_CAPTURE available=\(action != nil) hostResolved=\(applicationID != nil)")
        }

        func attempt(for requestID: UUID) -> Bool {
            guard self.requestID == requestID,
                Date().timeIntervalSince(capturedAt) < 360,
                UIApplication.shared.applicationState == .active
            else { return false }
            // A system navigation action is a capability for this particular launch.
            // Consume our reference before calling it, so a second tap cannot reuse it.
            self.requestID = nil
            let candidate = action ?? findAction()
            action = nil
            guard let candidate,
                let destinations = objectGetter(candidate, name: "destinations") as? [NSNumber],
                destinations.count == 1, let destination = destinations.first,
                let method = class_getInstanceMethod(
                    type(of: candidate), NSSelectorFromString("sendResponseForDestination:")),
                method_getNumberOfArguments(method) == 3
            else {
                return openResolvedApplication()
            }
            // Validate the Objective-C ABI before invoking an undocumented method.
            let returnType = method_copyReturnType(method)
            guard let argumentType = method_copyArgumentType(method, 2) else {
                free(returnType)
                return false
            }
            defer {
                free(returnType)
                free(argumentType)
            }
            guard String(cString: returnType) == "B", String(cString: argumentType) == "Q" else {
                print("FLYPE_RETURN_UNSUPPORTED_SIGNATURE")
                return false
            }
            typealias SendResponse = @convention(c) (AnyObject, Selector, UInt64) -> Bool
            let send = unsafeBitCast(method_getImplementation(method), to: SendResponse.self)
            let accepted = send(candidate, NSSelectorFromString("sendResponseForDestination:"), destination.uint64Value)
            print("FLYPE_RETURN_REQUEST accepted=\(accepted)")
            return accepted
        }

        private func openResolvedApplication() -> Bool {
            defer { applicationID = nil }
            guard let applicationID, applicationID != Bundle.main.bundleIdentifier,
                applicationID.count < 256,
                applicationID.range(of: "^[A-Za-z0-9-]+(?:\\.[A-Za-z0-9-]+)+$", options: .regularExpression) != nil,
                let workspaceClass = NSClassFromString("LSApplicationWorkspace"),
                class_getClassMethod(workspaceClass, NSSelectorFromString("defaultWorkspace")) != nil,
                let workspace = (workspaceClass as AnyObject).perform(NSSelectorFromString("defaultWorkspace"))?
                    .takeUnretainedValue() as? NSObject,
                let method = class_getInstanceMethod(
                    type(of: workspace), NSSelectorFromString("openApplicationWithBundleID:")),
                method_getNumberOfArguments(method) == 3
            else {
                print("FLYPE_RETURN_UNAVAILABLE")
                return false
            }
            let returnType = method_copyReturnType(method)
            guard let argumentType = method_copyArgumentType(method, 2) else {
                free(returnType)
                return false
            }
            defer {
                free(returnType)
                free(argumentType)
            }
            guard String(cString: returnType) == "B", String(cString: argumentType).hasPrefix("@") else { return false }
            typealias OpenApplication = @convention(c) (AnyObject, Selector, NSString) -> Bool
            let open = unsafeBitCast(method_getImplementation(method), to: OpenApplication.self)
            let accepted = open(
                workspace, NSSelectorFromString("openApplicationWithBundleID:"), applicationID as NSString)
            print("FLYPE_RETURN_HOST_REQUEST accepted=\(accepted)")
            return accepted
        }

        private func findAction() -> NSObject? {
            let app = UIApplication.shared
            let owners: [NSObject] =
                [app]
                + app.connectedScenes
                .filter { $0.activationState == .foregroundActive }
                .map { $0 as NSObject }
            for owner in owners {
                if let value = objectGetter(owner, name: "_systemNavigationAction") { return value }
                if let ivar = class_getInstanceVariable(type(of: owner), "_systemNavigationAction"),
                    let encoding = ivar_getTypeEncoding(ivar), String(cString: encoding).hasPrefix("@"),
                    let value = object_getIvar(owner, ivar) as? NSObject
                {
                    return value
                }
            }
            return nil
        }

        private func objectGetter(_ object: NSObject, name: String) -> NSObject? {
            let selector = NSSelectorFromString(name)
            guard let method = class_getInstanceMethod(type(of: object), selector),
                method_getNumberOfArguments(method) == 2
            else { return nil }
            let encoding = method_copyReturnType(method)
            defer { free(encoding) }
            guard String(cString: encoding).hasPrefix("@") else { return nil }
            return object.perform(selector)?.takeUnretainedValue() as? NSObject
        }
    }
#endif
