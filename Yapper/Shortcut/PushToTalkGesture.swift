/// The only keyboard state Yapper ever looks at: whether fn (Globe) and Shift are down.
/// Deliberately has no key codes, characters, or other modifiers.
struct ModifierSnapshot: Equatable, Sendable {
    var function: Bool
    var shift: Bool
}

/// Push-to-talk gesture: hold fn (Globe) + Shift. Pressed once when both are down (in either order),
/// released once when either goes up. Snapshots that do not change that answer emit nothing.
struct PushToTalkGesture: Sendable {
    private(set) var isHeld = false

    mutating func update(_ modifiers: ModifierSnapshot) -> ShortcutEvent? {
        let down = modifiers.function && modifiers.shift
        guard down != isHeld else { return nil }
        isHeld = down
        return down ? .pressed : .released
    }

    /// Forgets the held state; returns `.released` if a press was outstanding, so every press is paired.
    mutating func reset() -> ShortcutEvent? {
        guard isHeld else { return nil }
        isHeld = false
        return .released
    }
}
