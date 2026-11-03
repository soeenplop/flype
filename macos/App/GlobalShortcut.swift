import AppKit
import ApplicationServices
import Carbon.HIToolbox
import FlypeCore
import IOKit.hidsystem

/// The App Store build runs in a sandbox, where inserting into other apps is not available.
enum MacEnvironment {
    static var isSandboxed: Bool { ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil }
}

extension DictationKey {
    fileprivate static let allModifiers =
        UInt(NX_DEVICELCMDKEYMASK) | UInt(NX_DEVICERCMDKEYMASK) | UInt(NX_DEVICELALTKEYMASK)
        | UInt(NX_DEVICERALTKEYMASK) | UInt(NX_DEVICELCTLKEYMASK) | UInt(NX_DEVICERCTLKEYMASK)
        | UInt(NX_DEVICELSHIFTKEYMASK) | UInt(NX_DEVICERSHIFTKEYMASK) | NSEvent.ModifierFlags.function.rawValue
    /// Zero for a key that is not a modifier.
    fileprivate var modifierMask: UInt {
        switch keyCode {
        case 54: UInt(NX_DEVICERCMDKEYMASK)
        case 55: UInt(NX_DEVICELCMDKEYMASK)
        case 56: UInt(NX_DEVICELSHIFTKEYMASK)
        case 58: UInt(NX_DEVICELALTKEYMASK)
        case 59: UInt(NX_DEVICELCTLKEYMASK)
        case 60: UInt(NX_DEVICERSHIFTKEYMASK)
        case 61: UInt(NX_DEVICERALTKEYMASK)
        case 62: UInt(NX_DEVICERCTLKEYMASK)
        case 63: NSEvent.ModifierFlags.function.rawValue
        default: 0
        }
    }
    /// Every modifier that turns this key into a combination.
    fileprivate var otherModifiersMask: UInt { Self.allModifiers & ~modifierMask }
}

@MainActor
final class GlobalShortcut {
    private var hotKey: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var holdTask: Task<Void, Never>?
    private var state = DictationShortcut()
    private var key = DictationKey.current()
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?
    private var plainKeyHeld = false
    private var keyObserver: NSObjectProtocol?
    /// True while the settings wait for a new key, so pressing it does not start dictation.
    var paused = false {
        didSet { if paused { deliver(state.interrupt()) } }
    }
    var onArm: (() -> Void)?
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onCancel: (() -> Void)?
    var onUserInteraction: (() -> Void)?

    func start() -> Bool {
        if MacEnvironment.isSandboxed { return startHotKey() }
        guard AXIsProcessTrusted() else {
            stop()
            return false
        }
        key = DictationKey.current()
        guard key.isModifier || startFilter() else {
            stop()
            return false
        }
        if keyObserver == nil {
            keyObserver = NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.applyChosenKey() }
            }
        }
        if globalMonitor != nil, localMonitor != nil { return true }
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event, local: false) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event, local: true) }
            return event
        }
        guard globalMonitor != nil, localMonitor != nil else {
            stop()
            return false
        }
        return true
    }
    /// A registered key combination needs no permission: hold Control, Option and Space to dictate.
    private func startHotKey() -> Bool {
        if hotKey != nil { return true }
        var events = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                let shortcut = Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue()
                let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
                MainActor.assumeIsolated {
                    if pressed {
                        shortcut.onArm?()
                        shortcut.onPress?()
                    } else {
                        shortcut.onRelease?()
                    }
                }
                return noErr
            }, events.count, &events, Unmanaged.passUnretained(self).toOpaque(), &hotKeyHandler)
        guard status == noErr else { return false }
        let id = EventHotKeyID(signature: OSType(0x464C_5950), id: 1)
        let registered = RegisterEventHotKey(
            UInt32(kVK_Space), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &hotKey)
        guard registered == noErr else {
            stop()
            return false
        }
        return true
    }
    private func handle(_ event: NSEvent, local: Bool) {
        if event.cgEvent?.getIntegerValueField(.eventSourceUserData) == TextDestination.insertionEventTag { return }
        if paused { return }
        // The chosen key is no user action, whether or not the filter has already taken it.
        if !key.isModifier, event.type == .keyDown, event.keyCode == key.keyCode,
            plainKeyHeld || event.modifierFlags.rawValue & DictationKey.allModifiers == 0
        {
            return
        }
        // User actions after release invalidate a pending insertion, including custom editors
        // whose accessibility tree cannot distinguish the individual cursor position.
        // Modifier transitions do not move the caret or edit text. They can also arrive
        // after the dictation key release and must not discard the pending result.
        if event.type != .flagsChanged { onUserInteraction?() }
        // The floating stop button must receive its click before ending the held recording.
        if local, event.type != .flagsChanged, event.type != .keyDown { return }
        guard AXIsProcessTrusted() else {
            stop()
            return
        }
        if event.type == .flagsChanged {
            if event.keyCode != key.keyCode { deliver(state.interrupt()) }
            let flags = event.modifierFlags.rawValue
            let down = key.isModifier ? flags & key.modifierMask != 0 : plainKeyHeld
            setHeld(down, otherModifier: flags & key.otherModifiersMask != 0)
        } else {
            deliver(state.interrupt())
        }
    }
    private func setHeld(_ down: Bool, otherModifier: Bool) {
        deliver(state.update(keyDown: down, otherModifier: otherModifier, now: ProcessInfo.processInfo.systemUptime))
        if down, holdTask == nil {
            holdTask = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self, self.state.isHeld else { return }
                    guard AXIsProcessTrusted() else {
                        self.stop()
                        return
                    }
                    self.deliver(self.state.advance(now: ProcessInfo.processInfo.systemUptime))
                    try? await Task.sleep(for: .milliseconds(20))
                }
            }
        } else if !down {
            holdTask?.cancel()
            holdTask = nil
        }
    }
    /// Without this tap a chosen letter or function key would also reach the app in front. It only takes
    /// the key pressed alone, so combinations with it keep working.
    private func filter(_ type: CGEventType, _ event: CGEvent) -> CGEvent? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return event
        }
        guard !paused, !key.isModifier, event.getIntegerValueField(.keyboardEventKeycode) == Int64(key.keyCode),
            event.getIntegerValueField(.eventSourceUserData) != TextDestination.insertionEventTag
        else { return event }
        if type == .keyUp {
            guard plainKeyHeld else { return event }
            plainKeyHeld = false
            setHeld(false, otherModifier: false)
            return nil
        }
        // Key repeats of the held key disappear with it.
        if plainKeyHeld { return nil }
        guard event.flags.isDisjoint(with: [.maskCommand, .maskControl, .maskAlternate, .maskShift]),
            event.getIntegerValueField(.keyboardEventAutorepeat) == 0
        else { return event }
        plainKeyHeld = true
        setHeld(true, otherModifier: false)
        return nil
    }
    private func startFilter() -> Bool {
        if eventTap != nil { return true }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.keyUp.rawValue)
        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask,
                callback: { _, type, event, context in
                    guard let context else { return Unmanaged.passUnretained(event) }
                    let shortcut = Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue()
                    let result = MainActor.assumeIsolated { shortcut.filter(type, event) }
                    return result.map { Unmanaged.passUnretained($0) }
                }, userInfo: Unmanaged.passUnretained(self).toOpaque()),
            let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        else { return false }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        eventTap = tap
        eventTapSource = source
        return true
    }
    private func stopFilter() {
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
        if let eventTapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapSource, .commonModes) }
        eventTap = nil
        eventTapSource = nil
        plainKeyHeld = false
    }
    /// The choice can also arrive through sync, so a key held from before never counts.
    private func applyChosenKey() {
        let chosen = DictationKey.current()
        guard chosen != key else { return }
        deliver(state.interrupt())
        state = DictationShortcut()
        holdTask?.cancel()
        holdTask = nil
        plainKeyHeld = false
        key = chosen
        if key.isModifier { stopFilter() } else { _ = startFilter() }
    }
    private func deliver(_ action: DictationShortcut.Action?) {
        switch action {
        case .armed: onArm?()
        case .started: onPress?()
        case .finished: onRelease?()
        case .cancelled: onCancel?()
        case nil: break
        }
    }
    func stop() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        if let hotKeyHandler { RemoveEventHandler(hotKeyHandler) }
        hotKeyHandler = nil
        holdTask?.cancel()
        holdTask = nil
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        if let keyObserver { NotificationCenter.default.removeObserver(keyObserver) }
        keyObserver = nil
        stopFilter()
        deliver(state.interrupt())
        state = DictationShortcut()
    }
}
