import Foundation
import Observation

/// Composition root and app-level controller: owns the adapters, wires push-to-talk events into the
/// dictation coordinator, and exposes permission/readiness status plus user intents to StatusUI.
@MainActor
@Observable
final class AppComposition {
    let coordinator: DictationCoordinator
    /// True while the fn + Shift event tap is installed and delivering events.
    private(set) var isPushToTalkActive = false
    /// Why push-to-talk could not be turned on or stopped; nil when it is fine or merely awaiting permission.
    private(set) var shortcutError: ShortcutError?
    /// nil until first checked.
    private(set) var inputMonitoringPermission: PermissionStatus?
    private(set) var microphonePermission: PermissionStatus?
    private(set) var accessibilityPermission: PermissionStatus?
    private(set) var transcriptionReadiness: TranscriptionAvailability?
    private(set) var modelInstall: ModelInstallState = .idle
    private(set) var transcriptMode: TranscriptMode = .standard
    /// nil until first checked. Needed only by AI and Notes modes.
    private(set) var formattingAvailability: FormattingAvailability?

    @ObservationIgnored private let audioCapture: any AudioCapturing
    @ObservationIgnored private let transcriber: any SpeechTranscribing
    @ObservationIgnored private let textInserter: any TextInserting
    @ObservationIgnored private let formatter: any TranscriptFormatting
    @ObservationIgnored private let shortcutMonitor: any ShortcutMonitoring
    @ObservationIgnored private let preferences: any PreferencesStoring
    @ObservationIgnored private let fallbackLocale: Locale
    @ObservationIgnored private var settings: AppPreferences
    @ObservationIgnored private var dispatcher: ShortcutEventDispatcher?
    /// False once `stop()` begins, so queued shortcut events cannot start or finish a session.
    @ObservationIgnored private var acceptsShortcutEvents = false

    init(
        audioCapture: any AudioCapturing,
        transcriber: any SpeechTranscribing,
        textInserter: any TextInserting,
        formatter: any TranscriptFormatting,
        shortcutMonitor: any ShortcutMonitoring,
        preferences: any PreferencesStoring,
        fallbackLocale: Locale = .current
    ) {
        self.audioCapture = audioCapture
        self.transcriber = transcriber
        self.textInserter = textInserter
        self.formatter = formatter
        self.shortcutMonitor = shortcutMonitor
        self.preferences = preferences
        self.fallbackLocale = fallbackLocale
        settings = .defaults(locale: fallbackLocale)
        coordinator = DictationCoordinator(
            audioCapture: audioCapture, transcriber: transcriber, textInserter: textInserter, formatter: formatter,
            locale: fallbackLocale)
    }

    /// Loads preferences (or defaults), then checks status, which turns on push-to-talk if Input
    /// Monitoring is already granted. Gesture events are serialized into the coordinator: each is
    /// awaited before the next is handled.
    func start() async {
        settings = preferences.load() ?? .defaults(locale: fallbackLocale)
        coordinator.locale = Locale(identifier: settings.localeIdentifier)
        coordinator.mode = settings.transcriptMode
        transcriptMode = settings.transcriptMode
        dispatcher = ShortcutEventDispatcher { [weak self] event in await self?.deliver(event) }
        acceptsShortcutEvents = true
        await refreshStatus()
    }

    /// Removes the event tap and cancels any active dictation. A held gesture is abandoned,
    /// not finished, so quitting never inserts text.
    func stop() async {
        acceptsShortcutEvents = false
        shortcutMonitor.stop()
        isPushToTalkActive = false
        await dispatcher?.waitUntilIdle()
        await coordinator.cancel()
    }

    /// Re-reads permissions and model readiness, and turns push-to-talk on or off to match Input
    /// Monitoring. Never prompts and never downloads.
    func refreshStatus() async {
        inputMonitoringPermission = shortcutMonitor.permissionStatus()
        syncPushToTalk()
        accessibilityPermission = textInserter.accessibilityStatus()
        microphonePermission = await audioCapture.permissionStatus()
        formattingAvailability = formatter.availability()
        transcriptionReadiness = await transcriber.availability(for: coordinator.locale)
    }

    /// Picks how transcripts are shaped (from the next dictation on) and saves the choice.
    func selectTranscriptMode(_ mode: TranscriptMode) {
        transcriptMode = mode
        coordinator.mode = mode
        settings.transcriptMode = mode
        preferences.save(settings)
        formattingAvailability = formatter.availability()
    }

    /// Shows the system microphone prompt if the user has not decided yet. Call only from a user action.
    func requestMicrophoneAccess() async {
        microphonePermission = await audioCapture.requestPermission()
    }

    /// Shows the system Input Monitoring prompt if the user has not decided yet. Call only from a user action.
    /// A grant turns push-to-talk on immediately when macOS allows it; otherwise a later refresh picks it up.
    func requestInputMonitoringAccess() {
        inputMonitoringPermission = shortcutMonitor.requestPermission()
        syncPushToTalk()
    }

    /// Shows the system Accessibility prompt (it links to System Settings). Call only from a user action.
    /// The grant happens outside the app, so the status is picked up by a later `refreshStatus()`.
    func requestAccessibilityAccess() {
        textInserter.requestAccessibilityPermission()
    }

    /// First step of a model download: offered only when the locale's model is missing.
    /// Nothing is downloaded until `confirmModelDownload()`.
    func requestModelDownload() {
        guard transcriptionReadiness == .modelNotInstalled, modelInstall != .installing else { return }
        modelInstall = .awaitingConfirmation
    }

    func declineModelDownload() {
        guard modelInstall == .awaitingConfirmation else { return }
        modelInstall = .idle
    }

    /// Downloads and installs the on-device model from Apple, only after `requestModelDownload()`.
    /// The model is fetched from Apple's servers; audio is never sent anywhere.
    func confirmModelDownload() async {
        guard modelInstall == .awaitingConfirmation else { return }
        modelInstall = .installing
        do {
            try await transcriber.prepare(for: coordinator.locale)
            modelInstall = .idle
        } catch {
            modelInstall = .failed(error)
        }
        transcriptionReadiness = await transcriber.availability(for: coordinator.locale)
    }

    func cancelDictation() async {
        await coordinator.cancel()
    }

    /// Installs the tap only after `start()`, before `stop()`, and with Input Monitoring granted;
    /// removes it if the permission was revoked.
    private func syncPushToTalk() {
        guard acceptsShortcutEvents, let dispatcher else { return }
        guard inputMonitoringPermission == .authorized else {
            shortcutMonitor.stop()
            isPushToTalkActive = false
            shortcutError = nil
            return
        }
        guard !shortcutMonitor.isRunning else { return }
        do {
            try shortcutMonitor.start(
                onEvent: dispatcher.enqueue,
                onFailure: { [weak self] error in self?.pushToTalkFailed(error) })
            isPushToTalkActive = true
            shortcutError = nil
        } catch {
            isPushToTalkActive = false
            shortcutError = error
        }
    }

    private func pushToTalkFailed(_ error: ShortcutError) {
        isPushToTalkActive = false
        shortcutError = error
    }

    private func deliver(_ event: ShortcutEvent) async {
        guard acceptsShortcutEvents else { return }
        await coordinator.handle(event)
    }
}
