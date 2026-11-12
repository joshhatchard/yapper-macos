import CoreGraphics

/// What the modifier event tap reports to the app. Built from an event's type and flags only.
enum ModifierTapEvent: Equatable, Sendable {
    case modifiersChanged(ModifierSnapshot)
    /// macOS disabled the tap (callback timeout or user input); it must be re-enabled.
    case disabled
}

extension ModifierSnapshot {
    /// Keeps only `maskSecondaryFn` (fn/Globe) and `maskShift`; every other flag is dropped.
    init(_ flags: CGEventFlags) {
        self.init(function: flags.contains(.maskSecondaryFn), shift: flags.contains(.maskShift))
    }
}

/// Pure configuration and translation for the Core Graphics modifier tap.
enum ModifierTapMapping {
    /// Only modifier-flag changes. Key down/up events (and therefore key codes and text) are never delivered.
    static let eventsOfInterest = CGEventMask(1) << CGEventType.flagsChanged.rawValue
    /// Passive observer: the tap cannot modify, delay, or swallow events.
    static let options = CGEventTapOptions.listenOnly
    static let location = CGEventTapLocation.cgSessionEventTap
    static let placement = CGEventTapPlacement.tailAppendEventTap

    /// Reads nothing but the event type and, for `flagsChanged`, the fn and shift bits.
    static func signal(type: CGEventType, flags: CGEventFlags) -> ModifierTapEvent? {
        switch type {
        case .flagsChanged: .modifiersChanged(ModifierSnapshot(flags))
        case .tapDisabledByTimeout, .tapDisabledByUserInput: .disabled
        default: nil
        }
    }
}
