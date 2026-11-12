/// Push-to-talk on hold fn (Globe) + Shift, built on an injected modifier tap and Input Monitoring check.
///
/// The tap is installed only by `start`, and only when Input Monitoring is already authorized; the
/// permission prompt appears only through `requestPermission()`. Every press is paired with a release,
/// including when the tap is stopped, replaced, or disabled by macOS while held.
@MainActor
final class PushToTalkMonitor: ShortcutMonitoring {
    private let tap: any ModifierEventTapping
    private let authorization: any InputMonitoringAuthorizing
    private var gesture = PushToTalkGesture()
    private var onEvent: (@MainActor (ShortcutEvent) -> Void)?
    private var onFailure: (@MainActor (ShortcutError) -> Void)?
    /// Identifies the live tap; events tagged with an older value are stale and dropped.
    private var generation = 0

    init(tap: any ModifierEventTapping, authorization: any InputMonitoringAuthorizing) {
        self.tap = tap
        self.authorization = authorization
    }

    var isRunning: Bool { onEvent != nil }

    func permissionStatus() -> PermissionStatus {
        authorization.status()
    }

    func requestPermission() -> PermissionStatus {
        authorization.request()
        return authorization.status()
    }

    func start(
        onEvent: @escaping @MainActor (ShortcutEvent) -> Void,
        onFailure: @escaping @MainActor (ShortcutError) -> Void
    ) throws(ShortcutError) {
        stop()
        guard authorization.status() == .authorized else { throw .permissionDenied }
        let current = generation
        try tap.start { [weak self] event in self?.receive(event, generation: current) }
        self.onEvent = onEvent
        self.onFailure = onFailure
    }

    func stop() {
        guard let onEvent else { return }
        generation += 1
        self.onEvent = nil
        onFailure = nil
        tap.stop()
        if let edge = gesture.reset() { onEvent(edge) }
    }

    private func receive(_ event: ModifierTapEvent, generation: Int) {
        guard generation == self.generation, let onEvent else { return }
        switch event {
        case .modifiersChanged(let modifiers):
            if let edge = gesture.update(modifiers) { onEvent(edge) }
        case .disabled:
            recoverFromDisabledTap()
        }
    }

    /// Changes made while the tap was off were missed, so resync from the current keyboard state.
    private func recoverFromDisabledTap() {
        guard tap.reenable() else {
            let onFailure = onFailure
            stop()
            onFailure?(.eventTapDisabled)
            return
        }
        if let edge = gesture.update(tap.currentModifiers()) { onEvent?(edge) }
    }
}
