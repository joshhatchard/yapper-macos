extension AppComposition {
    /// Real adapters. Constructing them has no side effects beyond deleting crash-leftover
    /// recordings: no event tap is installed, nothing is prompted or downloaded until `start()` and user intents.
    static func live() -> AppComposition {
        AppComposition(
            audioCapture: MicrophoneCapture(),
            transcriber: SpeechAnalyzerTranscriber(),
            textInserter: AccessibilityTextInserter(
                accessibility: SystemAccessibility(), workspace: SystemWorkspace(), paste: SystemPaste()),
            formatter: FoundationModelsFormatter(),
            shortcutMonitor: PushToTalkMonitor(
                tap: CoreGraphicsModifierTap(), authorization: SystemInputMonitoringAuthorization()),
            preferences: UserDefaultsPreferencesStore()
        )
    }
}
