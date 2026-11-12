import Foundation
import Testing

@testable import Yapper

/// AppComposition with in-memory fakes and the real `PushToTalkMonitor` over a fake modifier tap.
@MainActor
@Suite("AppComposition")
struct AppCompositionTests {
    let capture = FakeAudioCapture()
    let transcriber = FakeTranscriber()
    let inserter = FakeTextInserter()
    let formatter = FakeFormatter()
    let tap = FakeModifierTap()
    let inputMonitoring = FakeInputMonitoringAuthorization()
    let preferences = FakePreferencesStore()
    let stored = AppPreferences(localeIdentifier: "en_GB")

    func makeComposition() -> AppComposition {
        AppComposition(
            audioCapture: capture,
            transcriber: transcriber,
            textInserter: inserter,
            formatter: formatter,
            shortcutMonitor: PushToTalkMonitor(tap: tap, authorization: inputMonitoring),
            preferences: preferences,
            fallbackLocale: Locale(identifier: "en_AU")
        )
    }

    func holdFnShift() {
        tap.modifiers(function: true, shift: false)
        tap.modifiers(function: true, shift: true)
    }

    func letGo() {
        tap.modifiers(function: false, shift: true)
    }

    // MARK: Push-to-talk wiring

    @Test("start dictates in the stored locale and turns on push-to-talk when permitted")
    func startUsesStoredPreferences() async {
        preferences.stored = stored
        let composition = makeComposition()

        await composition.start()

        #expect(composition.coordinator.locale.identifier == "en_GB")
        #expect(tap.isInstalled)
        #expect(composition.isPushToTalkActive)
        #expect(composition.shortcutError == nil)
    }

    @Test("start without stored preferences uses the fallback locale")
    func startFallsBackToDefaults() async {
        let composition = makeComposition()

        await composition.start()

        #expect(composition.coordinator.locale.identifier == "en_AU")
    }

    @Test("holding and releasing fn + Shift runs one dictation into the focused app")
    func gestureDrivesDictation() async {
        let composition = makeComposition()
        await composition.start()

        holdFnShift()
        await yieldUntil { composition.coordinator.state == .recording }
        letGo()
        await yieldUntil { composition.coordinator.state == .completed }

        #expect(composition.coordinator.state == .completed)
        #expect(capture.startCount == 1)
        #expect(inserter.insertions == [.init(text: "hello world", target: .sample)])
    }

    @Test("a release during a slow microphone start is delivered after the start finishes")
    func gestureEventsAreSerialized() async {
        let gate = Gate()
        capture.startGate = gate
        let composition = makeComposition()
        await composition.start()

        holdFnShift()
        await yieldUntil { capture.startCount == 1 }
        letGo()
        gate.open()
        await yieldUntil { composition.coordinator.state == .completed }

        #expect(composition.coordinator.state == .completed)
        #expect(capture.stopCount == 1)
    }

    @Test("a tap macOS refuses is reported and push-to-talk stays off")
    func tapFailureIsReported() async {
        tap.startError = .eventTapUnavailable
        let composition = makeComposition()

        await composition.start()

        #expect(composition.shortcutError == .eventTapUnavailable)
        #expect(!composition.isPushToTalkActive)
        #expect(!tap.isInstalled)
    }

    @Test("a tap macOS disables for good is reported, and the next refresh tries again")
    func disabledTapIsReportedAndRetried() async {
        let composition = makeComposition()
        await composition.start()
        tap.reenableSucceeds = false

        tap.send(.disabled)

        #expect(composition.shortcutError == .eventTapDisabled)
        #expect(!composition.isPushToTalkActive)

        await composition.refreshStatus()

        #expect(tap.startCount == 2)
        #expect(composition.isPushToTalkActive)
        #expect(composition.shortcutError == nil)
    }

    @Test("stop while fn + Shift is held cancels the session instead of inserting")
    func stopCancelsHeldSession() async {
        let composition = makeComposition()
        await composition.start()
        holdFnShift()
        await yieldUntil { composition.coordinator.state == .recording }

        await composition.stop()

        #expect(composition.coordinator.state == .cancelled)
        #expect(!tap.isInstalled)
        #expect(!composition.isPushToTalkActive)
        #expect(capture.cancelCount == 1)
        #expect(inserter.insertions.isEmpty)
    }

    @Test("cancel intent aborts an active session")
    func cancelDictationIntent() async {
        let composition = makeComposition()
        await composition.start()
        holdFnShift()
        await yieldUntil { composition.coordinator.state == .recording }

        await composition.cancelDictation()

        #expect(composition.coordinator.state == .cancelled)
        #expect(capture.cancelCount == 1)
    }

    // MARK: Input Monitoring

    @Test(
        "without Input Monitoring the tap is never installed and nothing is requested",
        arguments: [PermissionStatus.notDetermined, .denied, .restricted])
    func noTapWithoutPermission(status: PermissionStatus) async {
        inputMonitoring.current = status
        let composition = makeComposition()

        await composition.start()
        await composition.refreshStatus()

        #expect(composition.inputMonitoringPermission == status)
        #expect(tap.startCount == 0)
        #expect(inputMonitoring.requestCount == 0)
        #expect(!composition.isPushToTalkActive)
        #expect(composition.shortcutError == nil)
    }

    @Test("Input Monitoring is requested only by the explicit intent, and a grant turns push-to-talk on")
    func requestInputMonitoringAccess() async {
        inputMonitoring.current = .notDetermined
        inputMonitoring.afterRequest = .authorized
        let composition = makeComposition()
        await composition.start()

        composition.requestInputMonitoringAccess()

        #expect(inputMonitoring.requestCount == 1)
        #expect(composition.inputMonitoringPermission == .authorized)
        #expect(tap.startCount == 1)
        #expect(composition.isPushToTalkActive)
    }

    @Test("a denied request leaves the tap off")
    func deniedRequestLeavesTapOff() async {
        inputMonitoring.current = .notDetermined
        inputMonitoring.afterRequest = .denied
        let composition = makeComposition()
        await composition.start()

        composition.requestInputMonitoringAccess()

        #expect(composition.inputMonitoringPermission == .denied)
        #expect(tap.startCount == 0)
    }

    @Test("a grant made in System Settings is picked up by refresh without prompting")
    func refreshPicksUpGrant() async {
        inputMonitoring.current = .denied
        let composition = makeComposition()
        await composition.start()

        inputMonitoring.current = .authorized
        await composition.refreshStatus()

        #expect(composition.isPushToTalkActive)
        #expect(inputMonitoring.requestCount == 0)
    }

    @Test("refreshing while push-to-talk is on does not reinstall the tap")
    func refreshKeepsRunningTap() async {
        let composition = makeComposition()
        await composition.start()

        await composition.refreshStatus()
        await composition.refreshStatus()

        #expect(tap.startCount == 1)
        #expect(tap.stopCount == 0)
    }

    @Test("revoking Input Monitoring turns push-to-talk off at the next refresh")
    func revokeStopsTap() async {
        let composition = makeComposition()
        await composition.start()

        inputMonitoring.current = .denied
        await composition.refreshStatus()

        #expect(!tap.isInstalled)
        #expect(!composition.isPushToTalkActive)
    }

    @Test("status refreshes before start never install the tap")
    func refreshBeforeStartIsInert() async {
        let composition = makeComposition()

        await composition.refreshStatus()

        #expect(tap.startCount == 0)
        #expect(composition.inputMonitoringPermission == .authorized)
    }

    @Test("after stop, refresh and the request intent never reinstall the tap")
    func stoppedCompositionStaysInert() async {
        let composition = makeComposition()
        await composition.start()
        await composition.stop()

        await composition.refreshStatus()
        composition.requestInputMonitoringAccess()

        #expect(tap.startCount == 1)
        #expect(!tap.isInstalled)
    }

    // MARK: Permissions and readiness

    @Test("start reports permissions and model readiness without prompting or downloading")
    func startReportsStatusWithoutSideEffects() async {
        capture.permission = .notDetermined
        inserter.accessibility = .denied
        transcriber.availability = .modelNotInstalled
        preferences.stored = stored
        let composition = makeComposition()

        await composition.start()

        #expect(composition.microphonePermission == .notDetermined)
        #expect(composition.accessibilityPermission == .denied)
        #expect(composition.transcriptionReadiness == .modelNotInstalled)
        #expect(transcriber.availabilityQueries.map(\.identifier) == ["en_GB"])
        #expect(capture.permissionRequests == 0)
        #expect(inserter.permissionRequests == 0)
        #expect(inputMonitoring.requestCount == 0)
        #expect(transcriber.prepared.isEmpty)
    }

    @Test("status is unknown until checked")
    func statusStartsUnknown() {
        let composition = makeComposition()

        #expect(composition.microphonePermission == nil)
        #expect(composition.accessibilityPermission == nil)
        #expect(composition.inputMonitoringPermission == nil)
        #expect(composition.transcriptionReadiness == nil)
    }

    @Test("refresh picks up permission changes made in System Settings")
    func refreshUpdatesStatus() async {
        inserter.accessibility = .denied
        let composition = makeComposition()
        await composition.start()

        inserter.accessibility = .authorized
        await composition.refreshStatus()

        #expect(composition.accessibilityPermission == .authorized)
    }

    @Test("microphone access is requested only by the explicit intent")
    func requestMicrophoneAccess() async {
        capture.permission = .notDetermined
        capture.permissionAfterRequest = .authorized
        let composition = makeComposition()
        await composition.start()

        await composition.requestMicrophoneAccess()

        #expect(capture.permissionRequests == 1)
        #expect(composition.microphonePermission == .authorized)
    }

    @Test("Accessibility access is requested only by the explicit intent")
    func requestAccessibilityAccess() async {
        let composition = makeComposition()
        await composition.start()

        composition.requestAccessibilityAccess()

        #expect(inserter.permissionRequests == 1)
    }

    // MARK: Speech model download

    func startWithModelMissing() async -> AppComposition {
        transcriber.availability = .modelNotInstalled
        preferences.stored = stored
        let composition = makeComposition()
        await composition.start()
        return composition
    }

    @Test("requesting a download only asks for confirmation")
    func requestAsksForConfirmation() async {
        let composition = await startWithModelMissing()

        composition.requestModelDownload()

        #expect(composition.modelInstall == .awaitingConfirmation)
        #expect(transcriber.prepared.isEmpty)
    }

    @Test("confirming installs the model for the dictation locale and reports ready")
    func confirmInstalls() async {
        let composition = await startWithModelMissing()
        composition.requestModelDownload()

        await composition.confirmModelDownload()

        #expect(transcriber.prepared.map(\.identifier) == ["en_GB"])
        #expect(composition.modelInstall == .idle)
        #expect(composition.transcriptionReadiness == .ready)
    }

    @Test("confirm without a pending request never downloads")
    func confirmWithoutRequestIsIgnored() async {
        let composition = await startWithModelMissing()

        await composition.confirmModelDownload()

        #expect(transcriber.prepared.isEmpty)
        #expect(composition.modelInstall == .idle)
    }

    @Test("declining the confirmation never downloads")
    func declineCancels() async {
        let composition = await startWithModelMissing()
        composition.requestModelDownload()

        composition.declineModelDownload()
        await composition.confirmModelDownload()

        #expect(transcriber.prepared.isEmpty)
        #expect(composition.modelInstall == .idle)
    }

    @Test(
        "no download is offered unless the model is missing",
        arguments: [TranscriptionAvailability.ready, .unsupportedLocale, .unavailable])
    func requestIgnoredUnlessModelMissing(availability: TranscriptionAvailability) async {
        transcriber.availability = availability
        let composition = makeComposition()
        await composition.start()

        composition.requestModelDownload()
        await composition.confirmModelDownload()

        #expect(composition.modelInstall == .idle)
        #expect(transcriber.prepared.isEmpty)
    }

    @Test("a failed download is reported and readiness re-checked")
    func failedDownloadIsReported() async {
        let composition = await startWithModelMissing()
        transcriber.prepareError = .modelUnavailable(Locale(identifier: "en_GB"))
        composition.requestModelDownload()

        await composition.confirmModelDownload()

        #expect(composition.modelInstall == .failed(.modelUnavailable(Locale(identifier: "en_GB"))))
        #expect(composition.transcriptionReadiness == .modelNotInstalled)
        #expect(transcriber.availabilityQueries.count == 2)
    }

    @Test("a second confirm while installing does not start another download")
    func confirmWhileInstallingIsIgnored() async {
        let gate = Gate()
        let composition = await startWithModelMissing()
        transcriber.prepareGate = gate
        composition.requestModelDownload()

        let first = Task { await composition.confirmModelDownload() }
        await yieldUntil { composition.modelInstall == .installing }
        let second = Task { await composition.confirmModelDownload() }
        await yieldUntil { transcriber.prepared.count > 1 }
        gate.open()
        await first.value
        await second.value

        #expect(transcriber.prepared.count == 1)
    }

    // MARK: Transcript mode

    @Test("start applies the stored transcript mode")
    func startUsesStoredMode() async {
        preferences.stored = AppPreferences(localeIdentifier: "en_GB", transcriptMode: .ai)
        let composition = makeComposition()

        await composition.start()

        #expect(composition.transcriptMode == .ai)
        #expect(composition.coordinator.mode == .ai)
    }

    @Test("selecting a mode applies it and saves it without losing the locale")
    func selectingModeSaves() async {
        preferences.stored = stored
        let composition = makeComposition()
        await composition.start()

        composition.selectTranscriptMode(.notes)

        #expect(composition.transcriptMode == .notes)
        #expect(composition.coordinator.mode == .notes)
        #expect(preferences.stored == AppPreferences(localeIdentifier: "en_GB", transcriptMode: .notes))
    }

    @Test("refreshing status reads whether on-device formatting is available")
    func refreshReadsFormattingAvailability() async {
        formatter.availabilityValue = .appleIntelligenceNotEnabled
        let composition = makeComposition()

        await composition.refreshStatus()

        #expect(composition.formattingAvailability == .appleIntelligenceNotEnabled)
    }
}
