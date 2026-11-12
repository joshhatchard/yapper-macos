@testable import Yapper

/// Stands in for the Core Graphics event tap. Tests deliver tap events with `send(_:)` / `modifiers(...)`.
@MainActor
final class FakeModifierTap: ModifierEventTapping {
    var startError: ShortcutError?
    var reenableSucceeds = true
    /// What `currentModifiers()` reports (the real keyboard state). `modifiers(...)` keeps it in sync.
    var current = ModifierSnapshot(function: false, shift: false)

    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var reenableCount = 0
    private(set) var isInstalled = false
    /// Kept after `stop()` so tests can simulate a late OS callback.
    private(set) var handler: (@MainActor (ModifierTapEvent) -> Void)?

    func start(onEvent: @escaping @MainActor (ModifierTapEvent) -> Void) throws(ShortcutError) {
        startCount += 1
        if let startError { throw startError }
        isInstalled = true
        handler = onEvent
    }

    func reenable() -> Bool {
        reenableCount += 1
        return reenableSucceeds
    }

    func currentModifiers() -> ModifierSnapshot { current }

    func stop() {
        stopCount += 1
        isInstalled = false
    }

    func send(_ event: ModifierTapEvent) {
        handler?(event)
    }

    /// A flagsChanged event with this fn/shift state.
    func modifiers(function: Bool, shift: Bool) {
        current = ModifierSnapshot(function: function, shift: shift)
        send(.modifiersChanged(current))
    }
}

/// Input Monitoring permission double. `afterRequest` is what the user answers in the system prompt.
@MainActor
final class FakeInputMonitoringAuthorization: InputMonitoringAuthorizing {
    var current: PermissionStatus = .authorized
    var afterRequest: PermissionStatus?

    private(set) var requestCount = 0

    func status() -> PermissionStatus { current }

    func request() {
        requestCount += 1
        if let afterRequest { current = afterRequest }
    }
}

/// Collects events and failures emitted by a monitor.
@MainActor
final class ShortcutEventRecorder {
    private(set) var events: [ShortcutEvent] = []
    private(set) var failures: [ShortcutError] = []

    func record(_ event: ShortcutEvent) {
        events.append(event)
    }

    func recordFailure(_ error: ShortcutError) {
        failures.append(error)
    }
}

/// Suspends callers of `wait()` until `open()` is called.
@MainActor
final class Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        for waiter in waiters { waiter.resume() }
        waiters = []
    }
}

/// Yields the main actor until `condition` holds or the attempt budget runs out.
@MainActor
func yieldUntil(_ condition: () -> Bool) async {
    for _ in 0..<1_000 where !condition() {
        await Task.yield()
    }
}
