import Testing

@testable import Yapper

@MainActor
@Suite("PushToTalkMonitor")
struct PushToTalkMonitorTests {
    let tap = FakeModifierTap()
    let authorization = FakeInputMonitoringAuthorization()
    let recorder = ShortcutEventRecorder()
    let monitor: PushToTalkMonitor

    init() {
        monitor = PushToTalkMonitor(tap: tap, authorization: authorization)
    }

    func start() throws {
        try monitor.start(onEvent: recorder.record, onFailure: recorder.recordFailure)
    }

    // MARK: Permission

    @Test(
        "without Input Monitoring permission the tap is never installed and nothing is requested",
        arguments: [PermissionStatus.notDetermined, .denied, .restricted])
    func startRequiresPermission(status: PermissionStatus) {
        authorization.current = status

        #expect(throws: ShortcutError.permissionDenied) { try start() }
        #expect(tap.startCount == 0)
        #expect(!monitor.isRunning)
        #expect(authorization.requestCount == 0)
    }

    @Test("status checks never prompt")
    func statusDoesNotPrompt() {
        authorization.current = .notDetermined

        #expect(monitor.permissionStatus() == .notDetermined)
        #expect(authorization.requestCount == 0)
    }

    @Test("requesting permission asks the system once and does not install the tap")
    func requestPermission() {
        authorization.current = .notDetermined
        authorization.afterRequest = .authorized

        #expect(monitor.requestPermission() == .authorized)
        #expect(authorization.requestCount == 1)
        #expect(tap.startCount == 0)
    }

    // MARK: Events

    @Test("with permission, holding fn + Shift presses and letting go releases")
    func forwardsGesture() throws {
        try start()

        tap.modifiers(function: true, shift: false)
        tap.modifiers(function: true, shift: true)
        tap.modifiers(function: false, shift: true)

        #expect(monitor.isRunning)
        #expect(tap.startCount == 1)
        #expect(recorder.events == [.pressed, .released])
    }

    @Test("shift first, then fn, with other modifier changes while held, still presses once")
    func otherModifiersDoNotDuplicate() throws {
        try start()

        tap.modifiers(function: false, shift: true)
        tap.modifiers(function: true, shift: true)
        tap.modifiers(function: true, shift: true)  // e.g. command pressed while holding
        tap.modifiers(function: true, shift: true)  // command released
        tap.modifiers(function: true, shift: false)
        tap.modifiers(function: false, shift: false)

        #expect(recorder.events == [.pressed, .released])
    }

    // MARK: Lifecycle

    @Test("stop removes the tap and ignores late events")
    func stopRemovesTap() throws {
        try start()

        monitor.stop()
        tap.modifiers(function: true, shift: true)

        #expect(tap.stopCount == 1)
        #expect(!tap.isInstalled)
        #expect(!monitor.isRunning)
        #expect(recorder.events.isEmpty)
    }

    @Test("stop while held emits the missing release once")
    func stopWhileHeldReleases() throws {
        try start()
        tap.modifiers(function: true, shift: true)

        monitor.stop()
        tap.modifiers(function: false, shift: false)

        #expect(recorder.events == [.pressed, .released])
    }

    @Test("stop without a running tap does nothing")
    func stopWhenIdleIsNoOp() {
        monitor.stop()

        #expect(tap.stopCount == 0)
    }

    @Test("a tap that macOS refuses is reported and leaves nothing running")
    func tapFailurePropagates() {
        tap.startError = .eventTapUnavailable

        #expect(throws: ShortcutError.eventTapUnavailable) { try start() }
        #expect(!monitor.isRunning)
        monitor.stop()
        #expect(tap.stopCount == 0)
    }

    @Test("starting again replaces the tap, releasing a held press and ignoring the old callback")
    func restartReplaces() throws {
        try start()
        tap.modifiers(function: true, shift: true)
        let stale = tap.handler

        try start()
        stale?(.modifiersChanged(ModifierSnapshot(function: false, shift: false)))
        tap.modifiers(function: true, shift: true)

        #expect(tap.stopCount == 1)
        #expect(tap.startCount == 2)
        #expect(recorder.events == [.pressed, .released, .pressed])
    }

    // MARK: Tap disabled by the system

    @Test("a disabled tap is re-enabled and a hold that is still down stays pressed")
    func disabledWhileStillHeld() throws {
        try start()
        tap.modifiers(function: true, shift: true)

        tap.send(.disabled)

        #expect(tap.reenableCount == 1)
        #expect(monitor.isRunning)
        #expect(recorder.events == [.pressed])
        #expect(recorder.failures.isEmpty)
    }

    @Test("a key let go while the tap was disabled releases once after re-enabling")
    func disabledMissedRelease() throws {
        try start()
        tap.modifiers(function: true, shift: true)
        tap.current = ModifierSnapshot(function: true, shift: false)

        tap.send(.disabled)  // no further flagsChanged arrives: the release happened while the tap was off

        #expect(tap.reenableCount == 1)
        #expect(recorder.events == [.pressed, .released])
    }

    @Test("if the tap cannot be re-enabled, the hold is released, the tap removed, and the failure reported")
    func reenableFailure() throws {
        try start()
        tap.modifiers(function: true, shift: true)
        tap.reenableSucceeds = false

        tap.send(.disabled)
        tap.modifiers(function: true, shift: true)

        #expect(recorder.events == [.pressed, .released])
        #expect(recorder.failures == [.eventTapDisabled])
        #expect(tap.stopCount == 1)
        #expect(!monitor.isRunning)
    }
}
