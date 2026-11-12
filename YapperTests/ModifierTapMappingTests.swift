import CoreGraphics
import Testing

@testable import Yapper

@Suite("ModifierTapMapping")
struct ModifierTapMappingTests {
    @Test(
        "only the fn and shift bits are read from event flags",
        arguments: [
            (CGEventFlags(), ModifierSnapshot(function: false, shift: false)),
            (CGEventFlags.maskSecondaryFn, ModifierSnapshot(function: true, shift: false)),
            (CGEventFlags.maskShift, ModifierSnapshot(function: false, shift: true)),
            (CGEventFlags([.maskSecondaryFn, .maskShift]), ModifierSnapshot(function: true, shift: true)),
            (
                CGEventFlags([
                    .maskSecondaryFn, .maskShift, .maskCommand, .maskAlternate, .maskControl, .maskAlphaShift,
                ]),
                ModifierSnapshot(function: true, shift: true)
            ),
            (
                CGEventFlags([.maskCommand, .maskAlternate, .maskControl, .maskNumericPad]),
                ModifierSnapshot(function: false, shift: false)
            ),
        ])
    func snapshotFromFlags(flags: CGEventFlags, expected: ModifierSnapshot) {
        #expect(ModifierSnapshot(flags) == expected)
    }

    @Test("a flagsChanged event becomes a modifier snapshot")
    func flagsChangedIsForwarded() {
        let signal = ModifierTapMapping.signal(type: .flagsChanged, flags: [.maskSecondaryFn, .maskShift])

        #expect(signal == .modifiersChanged(ModifierSnapshot(function: true, shift: true)))
    }

    @Test(
        "the system disabling the tap is reported so it can be re-enabled",
        arguments: [CGEventType.tapDisabledByTimeout, .tapDisabledByUserInput])
    func disabledIsReported(type: CGEventType) {
        #expect(ModifierTapMapping.signal(type: type, flags: []) == .disabled)
    }

    @Test(
        "any other event type is ignored, even if it carries fn and shift",
        arguments: [CGEventType.keyDown, .keyUp, .leftMouseDown, .scrollWheel, .null])
    func otherEventsAreIgnored(type: CGEventType) {
        #expect(ModifierTapMapping.signal(type: type, flags: [.maskSecondaryFn, .maskShift]) == nil)
    }

    @Test("the tap subscribes to flagsChanged only")
    func subscribesToFlagsChangedOnly() {
        #expect(ModifierTapMapping.eventsOfInterest == CGEventMask(1) << CGEventType.flagsChanged.rawValue)
    }

    @Test("the tap is listen-only, so it can never modify or swallow input")
    func isListenOnly() {
        #expect(ModifierTapMapping.options == .listenOnly)
        #expect(ModifierTapMapping.location == .cgSessionEventTap)
    }
}
