import CoreGraphics

/// `ModifierEventTapping` backed by a Core Graphics session event tap.
///
/// The tap is listen-only and subscribes to `flagsChanged` only (`ModifierTapMapping`), so it never sees
/// key-down/up events, key codes, or text, and cannot modify or swallow anything: the callback returns
/// every event unchanged. Only the fn and shift bits are forwarded. Needs Input Monitoring; without it
/// `CGEventTapCreate` fails or delivers nothing. The run-loop source is on the main run loop (common
/// modes), so callbacks arrive on the main thread, also while menus are tracking.
@MainActor
final class CoreGraphicsModifierTap: ModifierEventTapping {
    private var machPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var onEvent: (@MainActor (ModifierTapEvent) -> Void)?

    var isInstalled: Bool { machPort != nil }

    func start(onEvent: @escaping @MainActor (ModifierTapEvent) -> Void) throws(ShortcutError) {
        stop()
        guard
            let port = CGEvent.tapCreate(
                tap: ModifierTapMapping.location,
                place: ModifierTapMapping.placement,
                options: ModifierTapMapping.options,
                eventsOfInterest: ModifierTapMapping.eventsOfInterest,
                callback: modifierTapCallback,
                userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { throw .eventTapUnavailable }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            CFMachPortInvalidate(port)
            throw .eventTapUnavailable
        }
        machPort = port
        runLoopSource = source
        self.onEvent = onEvent
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
    }

    func reenable() -> Bool {
        guard let machPort else { return false }
        CGEvent.tapEnable(tap: machPort, enable: true)
        return CGEvent.tapIsEnabled(tap: machPort)
    }

    /// Modifier state only (`CGEventSourceFlagsState`); no key state or events are read.
    func currentModifiers() -> ModifierSnapshot {
        ModifierSnapshot(CGEventSource.flagsState(.combinedSessionState))
    }

    func stop() {
        onEvent = nil
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
        if let machPort {
            CGEvent.tapEnable(tap: machPort, enable: false)
            CFMachPortInvalidate(machPort)
            self.machPort = nil
        }
    }

    isolated deinit {
        stop()
    }

    fileprivate func deliver(_ event: ModifierTapEvent) {
        onEvent?(event)
    }
}

/// C callback on the main thread (the source is on the main run loop). `userInfo` is the unretained tap,
/// valid until `stop()` invalidates the port. Always returns the event untouched.
private func modifierTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if let userInfo, let signal = ModifierTapMapping.signal(type: type, flags: event.flags) {
        let address = UInt(bitPattern: userInfo)
        MainActor.assumeIsolated {
            let pointer = UnsafeRawPointer(bitPattern: address)!
            Unmanaged<CoreGraphicsModifierTap>.fromOpaque(pointer).takeUnretainedValue().deliver(signal)
        }
    }
    return Unmanaged.passUnretained(event)
}
