import Testing

@testable import Yapper

@Suite("PushToTalkGesture")
struct PushToTalkGestureTests {
    var gesture = PushToTalkGesture()

    static let none = ModifierSnapshot(function: false, shift: false)
    static let fnOnly = ModifierSnapshot(function: true, shift: false)
    static let shiftOnly = ModifierSnapshot(function: false, shift: true)
    static let both = ModifierSnapshot(function: true, shift: true)

    mutating func feed(_ snapshots: [ModifierSnapshot]) -> [ShortcutEvent] {
        snapshots.compactMap { gesture.update($0) }
    }

    @Test(
        "holding fn and shift presses once, whichever goes down first",
        arguments: [[fnOnly, both], [shiftOnly, both], [both]])
    mutating func pressesOnceInAnyOrder(sequence: [ModifierSnapshot]) {
        #expect(feed(sequence) == [.pressed])
        #expect(gesture.isHeld)
    }

    @Test(
        "letting go of either key releases once",
        arguments: [[fnOnly, none], [shiftOnly, none], [none]])
    mutating func releasesWhenEitherGoesUp(release: [ModifierSnapshot]) {
        _ = gesture.update(Self.both)

        #expect(feed(release) == [.released])
        #expect(!gesture.isHeld)
    }

    @Test("other modifier changes while held do not emit duplicate presses")
    mutating func repeatedSnapshotsWhileHeldAreIgnored() {
        // A flagsChanged for command/option/control while fn+shift stay down reads as `both` again.
        #expect(
            feed([Self.fnOnly, Self.both, Self.both, Self.both, Self.shiftOnly, Self.none]) == [.pressed, .released])
    }

    @Test("fn or shift alone never presses")
    mutating func singleKeyNeverPresses() {
        #expect(feed([Self.fnOnly, Self.none, Self.shiftOnly, Self.none]).isEmpty)
    }

    @Test("pressing again after a release starts a new hold")
    mutating func secondHoldPressesAgain() {
        #expect(feed([Self.both, Self.fnOnly, Self.both, Self.none]) == [.pressed, .released, .pressed, .released])
    }

    @Test("reset while held releases once; reset when idle does nothing")
    mutating func resetReleasesOnlyWhenHeld() {
        #expect(gesture.reset() == nil)
        _ = gesture.update(Self.both)

        #expect(gesture.reset() == .released)
        #expect(gesture.reset() == nil)
        #expect(!gesture.isHeld)
    }
}
