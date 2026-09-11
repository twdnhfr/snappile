import AppKit
import Carbon

@MainActor
public final class HotKeyController {
    private let onTrigger: () -> Void
    // Only mutated on the main actor; unsafe so that deinit can release the handles.
    nonisolated(unsafe) private var hotKey: EventHotKeyRef?
    nonisolated(unsafe) private var eventHandler: EventHandlerRef?
    nonisolated(unsafe) private var tap: CFMachPort?
    nonisolated(unsafe) private var tapSource: CFRunLoopSource?
    private var chord = OptionChordState()
    private var nextID: UInt32 = 1
    private var registeredKeyCode: UInt32?
    private var registeredModifiers: UInt32?
    public var doubleOptionEnabled = true { didSet { refreshOptionMonitoring() } }
    public var hasInputMonitoringPermission: Bool { CGPreflightListenEventAccess() }
    public private(set) var optionMonitoringError: String?
    public var isOptionMonitoringActive: Bool {
        guard let tap else { return false }
        return CFMachPortIsValid(tap) && CGEvent.tapIsEnabled(tap: tap)
    }

    public init(onTrigger: @escaping () -> Void) {
        self.onTrigger = onTrigger
        installCarbonHandler()
    }

    deinit {
        // Both callbacks hold an unretained pointer to this instance; tear them
        // down even when a client never called stop().
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
    }
    public func register(keyCode: UInt32, modifiers: UInt32) throws {
        guard eventHandler != nil else { throw HotKeyError.registrationFailed(OSStatus(eventNotHandledErr)) }
        if registeredKeyCode == keyCode, registeredModifiers == modifiers, hotKey != nil { return }
        var candidate: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x5350_4B59), id: nextID)
        let status = RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &candidate)
        guard status == noErr, let candidate else { throw HotKeyError.registrationFailed(status) }
        if let old = hotKey { UnregisterEventHotKey(old) }
        hotKey = candidate
        registeredKeyCode = keyCode
        registeredModifiers = modifiers
        nextID &+= 1
    }

    public func requestInputMonitoringPermission() {
        _ = CGRequestListenEventAccess()
        refreshOptionMonitoring()
    }
    public func refreshOptionMonitoring() {
        guard doubleOptionEnabled, hasInputMonitoringPermission else {
            stopTap()
            return
        }
        if let tap, !CGEvent.tapIsEnabled(tap: tap) { CGEvent.tapEnable(tap: tap, enable: true) }
        if tap == nil { installTap() }
    }
    public func stop() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        registeredKeyCode = nil
        registeredModifiers = nil
        stopTap()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    private func installCarbonHandler() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let controller = Unmanaged<HotKeyController>.fromOpaque(userData).takeUnretainedValue()
                var hotKeyID = EventHotKeyID()
                var size = MemoryLayout<EventHotKeyID>.size
                guard
                    GetEventParameter(
                        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                        nil, size, &size, &hotKeyID) == noErr,
                    hotKeyID.signature == OSType(0x5350_4B59), hotKeyID.id == controller.nextID &- 1
                else {
                    return OSStatus(eventNotHandledErr)
                }
                Task { @MainActor in controller.onTrigger() }
                return noErr
            }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
    }
    private func installTap() {
        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let controller = Unmanaged<HotKeyController>.fromOpaque(refcon).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = controller.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                } else {
                    MainActor.assumeIsolated { controller.handleOptionEvent(event) }
                }
                return Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else {
            optionMonitoringError = L10n.text(
                "The Option hotkey could not be started. Restart SnapPile after granting permission. The fallback shortcut will continue to work."
            )
            return
        }
        optionMonitoringError = nil
        // Seed from the current modifier flags, then use each event's exact state.
        let initial = OptionModifierSnapshot(rawFlags: CGEventSource.flagsState(.combinedSessionState).rawValue)
        _ = chord.update(leftDown: initial.leftDown, rightDown: initial.rightDown, blocked: true)
        tapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let tapSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), tapSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }
    private func stopTap() {
        if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tapSource = nil
        tap = nil
        chord = OptionChordState()
        optionMonitoringError = nil
    }
    private func handleOptionEvent(_ event: CGEvent) {
        let state = OptionModifierSnapshot(rawFlags: event.flags.rawValue)
        if chord.update(leftDown: state.leftDown, rightDown: state.rightDown, blocked: state.blocked) {
            DispatchQueue.main.async { [weak self] in self?.onTrigger() }
        }
    }
}

public enum HotKeyError: LocalizedError, Equatable {
    case registrationFailed(OSStatus)
    public var errorDescription: String? {
        switch self {
        case .registrationFailed(let status):
            return L10n.format("The keyboard shortcut could not be registered (OSStatus %d).", status)
        }
    }
}

/// Tracks the physical rising edge; releasing another modifier never arms a held chord.
public struct OptionChordState {
    private var wasBothDown = false
    public init() {}
    public mutating func update(leftDown: Bool, rightDown: Bool, blocked: Bool) -> Bool {
        let both = leftDown && rightDown
        let triggered = both && !wasBothDown && !blocked
        wasBothDown = both
        return triggered
    }
}

/// Device-specific modifier flags from Apple's IOKit/hidsystem/IOLLEvent.h.
/// These describe this event, avoiding a later global keyState query that can
/// disagree with a flagsChanged event or miss a quick press/release pair.
public struct OptionModifierSnapshot {
    public let leftDown: Bool
    public let rightDown: Bool
    public let blocked: Bool
    public init(rawFlags: UInt64) {
        let option = rawFlags & 0x0008_0000 != 0  // NX_ALTERNATEMASK
        leftDown = option && rawFlags & 0x20 != 0  // NX_DEVICELALTKEYMASK
        rightDown = option && rawFlags & 0x40 != 0  // NX_DEVICERALTKEYMASK
        blocked = rawFlags & 0x0016_0000 != 0  // Command, Control, Shift
    }
}
