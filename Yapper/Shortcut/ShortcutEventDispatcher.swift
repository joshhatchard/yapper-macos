/// Serializes push-to-talk events into an async handler such as `DictationCoordinator.handle(_:)`.
///
/// OS callbacks are synchronous; the coordinator is async and expects ordered events. Each event is
/// awaited before the next one is handed over. A release that arrives while its press is still queued
/// (the user tapped while a previous session was busy) cancels that press, so no zero-length session
/// is started late.
@MainActor
final class ShortcutEventDispatcher {
    private let handler: @MainActor (ShortcutEvent) async -> Void
    private var pending: [ShortcutEvent] = []
    private var drainTask: Task<Void, Never>?

    init(handler: @escaping @MainActor (ShortcutEvent) async -> Void) {
        self.handler = handler
    }

    /// Queues `event`. Matches the `onEvent` signature of `ShortcutMonitoring.register`.
    func enqueue(_ event: ShortcutEvent) {
        if event == .released, pending.last == .pressed {
            pending.removeLast()
            return
        }
        pending.append(event)
        guard drainTask == nil else { return }
        drainTask = Task { await drain() }
    }

    /// Returns once every queued event has been handled.
    func waitUntilIdle() async {
        while let drainTask { await drainTask.value }
    }

    private func drain() async {
        while !pending.isEmpty {
            await handler(pending.removeFirst())
        }
        drainTask = nil
    }
}
