/// Thin seam over the Core Graphics event tap that watches modifier keys. Real: `CoreGraphicsModifierTap`.
/// Reports only `ModifierTapEvent`s (fn/shift state, or that macOS disabled the tap).
@MainActor
protocol ModifierEventTapping: AnyObject {
    /// Installs and enables a listen-only tap. Throws `.eventTapUnavailable` if macOS refuses it.
    /// At most one tap is active; events arrive on the main thread.
    func start(onEvent: @escaping @MainActor (ModifierTapEvent) -> Void) throws(ShortcutError)

    /// Re-enables the tap after a `.disabled` event. Returns false if it is still disabled.
    func reenable() -> Bool

    /// The current fn/shift state, used to resynchronize after the tap was disabled.
    func currentModifiers() -> ModifierSnapshot

    /// Disables and removes the tap. No events are delivered afterwards.
    func stop()
}
