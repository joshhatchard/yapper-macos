import AppKit
import SwiftUI

/// Renders dictation status, permissions, and model readiness. Sends intents only; owns no audio,
/// speech, or permission logic. Every permission prompt and download starts from a button here.
struct MenuBarContentView: View {
    let app: AppComposition

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            dictationSection
            Divider()
            modeSection
            Divider()
            permissionsSection
            Divider()
            ModelSection(app: app)
            Divider()
            Button("Quit Yapper") {
                Task {
                    await app.stop()
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding()
        .frame(width: 340, alignment: .leading)
        .task { await app.refreshStatus() }
    }

    @ViewBuilder private var dictationSection: some View {
        Text(StatusPresentation.title(for: app.coordinator.state))
            .font(.headline)
            .fixedSize(horizontal: false, vertical: true)
        if let error = app.shortcutError {
            Text(StatusPresentation.message(for: error))
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        } else if app.isPushToTalkActive {
            Text(StatusPresentation.pushToTalkHint)
                .foregroundStyle(.secondary)
        } else {
            Text("Push-to-talk (fn + Shift) is off until Input Monitoring is allowed.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        if app.coordinator.state.isActive {
            Button("Cancel Dictation") { Task { await app.cancelDictation() } }
        }
    }

    /// Default / AI / Notes. Applies from the next dictation on.
    @ViewBuilder private var modeSection: some View {
        Text("Mode")
            .font(.subheadline.weight(.semibold))
        Picker(
            "Mode",
            selection: Binding(get: { app.transcriptMode }, set: { app.selectTranscriptMode($0) })
        ) {
            ForEach(TranscriptMode.allCases, id: \.self) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        Text(StatusPresentation.summary(for: app.transcriptMode))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        if app.transcriptMode != .standard, let note = StatusPresentation.formattingNote(app.formattingAvailability) {
            Text(note)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var permissionsSection: some View {
        switch app.inputMonitoringPermission {
        case nil:
            Text("Input Monitoring: checking…")
        case .authorized:
            Label("Input Monitoring allowed (fn + Shift only)", systemImage: "checkmark.circle")
        case .notDetermined:
            Button("Allow Input Monitoring…") { app.requestInputMonitoringAccess() }
            Text(
                "Needed to notice fn + Shift. Yapper reads only those two keys, never what you type, "
                    + "and never blocks keys."
            )
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        case .denied, .restricted:
            Text(
                "Input Monitoring is off. Enable Yapper in System Settings › Privacy & Security › "
                    + "Input Monitoring, then quit and reopen Yapper if fn + Shift does not respond."
            )
            .fixedSize(horizontal: false, vertical: true)
        }
        switch app.microphonePermission {
        case nil:
            Text("Microphone: checking…")
        case .authorized:
            Label("Microphone allowed", systemImage: "checkmark.circle")
        case .notDetermined:
            Button("Allow Microphone Access…") { Task { await app.requestMicrophoneAccess() } }
        case .denied, .restricted:
            Text("Microphone is off. Enable Yapper in System Settings › Privacy & Security › Microphone.")
                .fixedSize(horizontal: false, vertical: true)
        }
        switch app.accessibilityPermission {
        case nil:
            Text("Accessibility: checking…")
        case .authorized:
            Label("Accessibility allowed (to insert text)", systemImage: "checkmark.circle")
        case .notDetermined, .denied, .restricted:
            Button("Allow Accessibility Access…") { app.requestAccessibilityAccess() }
            Text("Needed to insert text. Enable Yapper in System Settings › Privacy & Security › Accessibility.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        Button("Refresh Permission Status") {
            Task { await app.refreshStatus() }
        }
        Text("After changing a permission in System Settings, refresh here if its status hasn't updated.")
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Model readiness plus the two-step, user-confirmed download.
private struct ModelSection: View {
    let app: AppComposition

    var body: some View {
        Text(StatusPresentation.readiness(app.transcriptionReadiness, locale: app.coordinator.locale))
            .fixedSize(horizontal: false, vertical: true)
        switch app.modelInstall {
        case .awaitingConfirmation:
            Text(
                "macOS will download this language's speech model from Apple (one time). "
                    + "Your audio is always transcribed on this Mac and never uploaded."
            )
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Download") { Task { await app.confirmModelDownload() } }
                    .keyboardShortcut(.defaultAction)
                Button("Not Now") { app.declineModelDownload() }
            }
        case .installing:
            ProgressView("Downloading speech model…")
        case .idle, .failed:
            if case .failed(let error) = app.modelInstall {
                Text(StatusPresentation.message(for: .transcription(error)))
                    .foregroundStyle(.red)
            }
            if app.transcriptionReadiness == .modelNotInstalled {
                Button("Download Speech Model…") { app.requestModelDownload() }
            }
        }
    }
}
