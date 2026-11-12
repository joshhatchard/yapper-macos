# Yapper: Architecture and Design Notes

This is the development log for Yapper. It covers the decisions behind each module, what was rejected and why, what is verified and what is not, and the manual test checklist. For an overview and build instructions, see the [README](../README.md).

## Status
Local macOS menu-bar app with strictly on-device transcription and formatting. This document is the source of truth for design decisions; revise it when they change.

## Approved shortcut change (implemented, see Shortcut slice)
The push-to-talk gesture is **hold Fn/Globe + Shift**, replacing an earlier Carbon hot-key shortcut. Implement it with a listen-only Core Graphics event tap observing only modifier-flag changes; detect when Fn and Shift are both down, start once, and stop when either is released. Do not inspect or retain ordinary key events, and do not modify or suppress events. Require Input Monitoring permission, show status clearly, and request it only after an explicit user action in the menu. Do not activate the tap without permission. Test the state machine through an injected event source; real hardware behavior and permission UX require manual verification.

## Goal
Build a small native macOS menu-bar app that lets the user invoke a global shortcut, dictate speech, and insert the resulting transcript into the currently focused application. Audio must not be sent to a server.

## Non-goals for the prototype
- Accounts, cloud backend, sync, billing, or analytics
- AI rewriting, style transfer, app-aware context, or custom vocabulary UI
- Persistent audio or transcript history
- Windows or mobile support
- Multiple speech-engine implementations before the first end-to-end path works

## Platform and technology
- Native macOS app using Swift, SwiftUI for app/settings UI, and AppKit where macOS integration requires it.
- Use Apple system frameworks for microphone capture, speech recognition, global shortcut handling, and text insertion.
- Evaluate Apple's modern SpeechAnalyzer/Transcriber API on the target macOS version. Keep the speech capability behind an app-owned protocol. If availability or reliability blocks the prototype, use Apple's SFSpeechRecognizer only when `supportsOnDeviceRecognition` is true and set the request to require on-device recognition. Never silently fall back to network transcription.
- Set the deployment target after confirming the chosen speech API and the user's intended macOS compatibility. Initial development/testing is on the user's macOS 26.6.2 machine.

## Architecture
Keep a single app target with small, cohesive modules and explicit boundaries. Avoid premature microservices, plugin systems, generic frameworks, and unnecessary dependencies.

### Modules and responsibilities
1. **AppShell** — app lifecycle, menu-bar entry point, composition root, dependency wiring.
2. **Dictation** — state machine and use case coordinating idle → recording → transcribing → completed/failed/cancelled.
3. **AudioCapture** — microphone permission, audio session/capture lifecycle, audio buffer or temporary-file ownership; no speech-recognition policy.
4. **SpeechTranscription** — protocol plus Apple Speech implementation; reports availability and typed errors; enforces on-device-only behavior.
5. **Shortcut** — hold fn (Globe) + Shift push-to-talk: listen-only Core Graphics `flagsChanged` event tap gated by Input Monitoring; emits paired press/release events. No dependency (see Shortcut slice).
6. **TextInsertion** — deliver completed text to the focused app via a clearly isolated pasteboard/accessibility adapter. Request and explain Accessibility permissions; do not inspect surrounding app text.
7. **Preferences** — persist only user settings (locale; optional launch-at-login later; the gesture is fixed); use platform storage and avoid storing audio/transcripts.
8. **StatusUI** — recording/transcribing/error feedback and basic settings. UI observes state; it does not own audio or speech logic.

### Dependency direction
`AppShell` wires concrete adapters into `Dictation`. `Dictation` depends on protocols for capture, transcription, and insertion. Platform adapters depend on Apple frameworks. UI sends user intents to the coordinator and renders observable state. Keep protocol surfaces small and driven by real seams; do not create interfaces for every type.

## Core behavior
1. User grants microphone and speech-recognition permissions with clear explanations.
2. Shortcut press starts capture and visible recording feedback.
3. Shortcut release stops capture and finalizes the recording.
4. Audio is transcribed on-device only. Unsupported locale, unavailable model/service, denied permission, and recognizer errors are surfaced clearly; no network fallback.
5. On successful non-empty transcription, insert text into the previously focused application.
6. Cancellation, empty audio, app focus changes, insertion failure, and repeated shortcut events are handled without leaving capture active or losing the UI state.
7. Raw audio and transcript are discarded after insertion or failure; no history in the first version.

## Quality and engineering practices
- Keep business coordination testable without microphone, OS permissions, or UI.
- Use Swift concurrency deliberately; isolate UI state to `@MainActor`; define cancellation and resource cleanup explicitly.
- Prefer value types for domain state and typed errors over stringly typed status/error handling.
- Add tests around observable behavior, state transitions, and failure cases. Use hardware/manual checks only for OS integration seams.
- Do not over-mock platform behavior; test app-owned logic with fakes and verify platform adapters through focused integration/manual checks.
- Add only dependencies that solve a demonstrated platform gap; record the reason and license.
- Keep privacy claims precise: app code must require on-device recognition and must not upload audio, while documenting any Apple system behavior relevant to the selected API.
- Add formatting/lint tooling only after checking available Swift tooling and selecting a compatible configuration; do not add a noisy or redundant toolchain.

## Delivery workflow
1. **Plan (current):** agree on scope, platform, privacy, and architecture; keep this file updated.
2. **Scaffold:** inspect installed Xcode/Swift tooling, create the minimal app/project structure, domain types, protocols, and empty function signatures only. No production behavior in this phase. Build the empty scaffold to catch project/configuration issues.
3. **Implement:** one vertical module/slice at a time. For each behavior, write a focused failing test first, run it to confirm the expected failure, implement the smallest change, rerun the test and relevant suite, then refactor while green. Start with dictation coordination/state transitions, then speech, capture, shortcut, insertion, and UI integration.
4. **Verify:** run the full test suite and configured formatter/linter/build checks after each meaningful slice. Resolve real compiler/test/lint failures before moving to the next module. Manually verify permissions, offline behavior, shortcut, and insertion in a second app.

## First milestone / acceptance criteria
- A native macOS menu-bar app launches and exposes clear status.
- A configurable or documented prototype shortcut starts and stops dictation.
- Microphone capture and transcription complete using on-device recognition only.
- Text is inserted into a focused text field in another app, or a clear actionable error is shown.
- Permissions denied, unsupported on-device locale, cancellation, and transcription failure leave the app in a recoverable state.
- Tests cover the coordinator's primary transitions and key failure paths; build succeeds with no unexplained warnings.
- No backend, network transcription, persistent audio, or transcript-history feature is present.

## Verified during scaffold
- Tooling: Xcode 27.0 (27A266a), Swift 6.4, macOS 27.0 SDK, host macOS 26.6.2. `swift format` ships in the Xcode toolchain; SwiftLint/xcodegen/tuist are not installed.
- Speech API: `SpeechAnalyzer`, `SpeechTranscriber`, and `AssetInventory` exist in the SDK, annotated `@available(anyAppleOS 26, *)`, including `analyzeSequence(from: AVAudioFile)`. Scaffold targets SpeechAnalyzer with deployment target **macOS 26.0**. Runtime findings are in the Speech slice section.
- Project: hand-written Xcode project (`objectVersion 77`, file-system synchronized groups), app target + hosted Swift Testing target, shared `Yapper` scheme, Swift 6 language mode. Not sandboxed (text insertion into other apps); hardened runtime with audio-input entitlement.
- Lint/format: `swift format lint --strict` with repo `.swift-format` (4-space indent, 120 columns). No extra dependency.
- Capture hands the transcriber a temporary audio file (`CapturedAudio`), discarded after each session.
- Build output must live outside `~/Desktop` (File Provider adds xattrs that make codesign fail). Use the default DerivedData or `-derivedDataPath ~/Library/Developer/Xcode/DerivedData/<name>`.

## Dictation slice (implemented, test-first)
- `DictationCoordinator` covered by 19 Swift Testing cases using in-memory fakes (`YapperTests/Support/DictationTestDoubles.swift`).
- Semantics: `completed`/`failed`/`cancelled` are the last outcome, not a lock; a new `start()` is allowed from any inactive state (`DictationState.isActive` = recording or transcribing). Press while active, release while not recording, and cancel while inactive are ignored.
- Insertion target is captured at start; no target fails with `.noInsertionTarget` before the mic opens. Accessibility not trusted fails with `.textInsertion(.accessibilityPermissionDenied)` before the target check and before the mic opens (never prompts). Whitespace-only transcripts fail with `.emptyTranscript`.
- Captured audio is discarded after every transcription attempt (success, failure, cancel) before the terminal state is published.
- Cancel during transcription drops the result (no insertion), even if the transcriber later errors.
- Contract for AppShell: await each `handle(_:)` call before the next shortcut event (serialize events).

### Open design issues (resolve before/with the relevant slice)
- `start()` sets `.recording` only after `startCapture()` returns, so a release arriving during that await is ignored. Safe only while events are serialized; a `.starting` state or deferred release is needed if not. (Resolved for shortcut input by `ShortcutEventDispatcher`, which queues the release until `start()` returns; covered by a test with the real coordinator.)
- Cancel during transcription does not stop the transcriber's work; it only drops the result. Real cancellation needs the coordinator to own a `Task` and the adapter to honor cooperative cancellation (`TranscriptionError.cancelled`).
- If `stopCapture()` throws, the capture adapter must guarantee it released the microphone; the coordinator does not call `cancelCapture()` in that path. (Resolved in the AudioCapture slice: `MicrophoneCapture.stopCapture()` releases the input and deletes the file before throwing.)
- `startCapture()` fails with `.permissionDenied` when microphone permission is `.notDetermined`, so the prompt never appears mid-press. AppShell/StatusUI must call `requestPermission()` up front (onboarding) and use `permissionStatus()` to tell "not asked yet" from "denied" when showing the error.
- `prepare(for:)`/`availability(for:)` are not used by the coordinator; AppComposition owns readiness and the user-confirmed download (see AppShell slice). The coordinator does not block recording when the model is missing; transcription then fails with `.modelUnavailable` and the menu offers the download.

## Speech slice (implemented, test-first)
- `SpeechAnalyzerMapping` (pure): asset status -> `TranscriptionAvailability`, framework errors -> `TranscriptionError`, final segments -> `Transcript`. 13 unit tests.
- `SpeechAnalyzerTranscriber` (adapter): `SpeechTranscriber` with no volatile results/alternatives/attributes, `SpeechAnalyzer.analyzeSequence(from: AVAudioFile)` + `finalizeAndFinish(through:)`, results collected in a child task. 11 integration tests against the real framework; model-dependent ones run only when the locale is already installed. Audio fixtures are generated locally (`/usr/bin/say`, silent/zero-frame WAV); no microphone, no network audio.
- Policy: `availability(for:)` and `transcribe` never download. Only `prepare(for:)` calls `AssetInventory.assetInstallationRequest` + `downloadAndInstall()`, and only when availability is `.modelNotInstalled`. UI must get user opt-in before calling `prepare` (it can download models from Apple).
- Error mapping: `CancellationError` -> `.cancelled`; SFSpeechError `cannotAllocateUnsupportedLocale` -> `.unsupportedLocale`; `noModel`/`assetLocaleNotAllocated`/`tooManyAssetLocalesAllocated` -> `.modelUnavailable`; anything else (incl. unreadable file) -> `.recognitionFailed(description)`.
- Cancellation: cancelling the calling task forwards to `cancelAndFinishNow()` and cancels the collector; verified by a test (and a mutation check: without forwarding the test fails).

### Verified at runtime (host macOS 26.6.2, Xcode 27 SDK, deployment 26.0)
- `SpeechTranscriber.isAvailable == true`; 30 supported locales (de, en, es, fr, it, ja, ko, pt, yue, zh variants). `maximumReservedLocales == 5`.
- Installed before this work: en-AU/CA/GB/IE/IN/NZ/SG/US/ZA. Unsupported identifiers (`xx_YY`, `tlh`) resolve to nil / `.unsupported`; reserving one throws SFSpeechError 15.
- `AssetInventory.status(forModules:)` reports `.supported` (not `.installed`) for a locale listed in `installedLocales` until the process reserves it, yet analysis works without reserving. Hence availability treats "in `installedLocales`" as ready. Reservations from unbundled CLI probes did not persist across processes.
- Real transcription of locally synthesized speech works: en_AU and en_US, 22.05 kHz AIFF from `say`, ~0.4 s for 4 s audio, ~1.5 s for 42 s audio. Final results arrive as sentence segments with leading spaces.
- No speech-recognition permission prompt or error occurred for SpeechAnalyzer in a CLI probe or the hosted test app. Not yet checked: behaviour in a signed app launched outside Xcode, and whether `NSSpeechRecognitionUsageDescription` is still needed. `TranscriptionError.permissionDenied` is currently never produced by this adapter.
- Silence (2 s) -> zero results. Zero-frame file: `analyzeSequence` returns nil and the results sequence never finishes even after `cancelAndFinishNow()` (hang). Adapter short-circuits zero-frame files to an empty transcript.
- `SpeechAnalyzer` does not react to Swift task cancellation by itself; explicit forwarding is required.
- `AssetInstallationRequest.progress.totalUnitCount` is 0 right after creation even when a download is needed. Do not use it to decide whether a download will happen; check availability first.

### Not verified / limitations
- Offline operation: not tested with networking disabled. Analysis ran locally with assets already present, but "fully offline" is unproven, and first use of a locale needs a model download from Apple.
- `prepare(for:)` download path is untested by automation (would download models). Needs a manual, user-approved run.
- Microphone-captured audio not yet exercised end to end; capture-format audio (48 kHz stereo, via the capture pipeline) from synthetic TTS is verified. Accuracy on real voices unknown.
- Probe side effect: an aborted `downloadAndInstall()` for fr_FR during probing still completed system-side; fr-BE/CA/CH/FR assets are now installed. There is no app-level uninstall API; the system manages these assets.
- Readiness UX decided: AppComposition checks `availability` at start and whenever the menu opens; `prepare` runs only after a two-step user confirmation (see AppShell slice).

## AudioCapture slice (implemented, test-first)
- `MicrophoneCapture` (actor, replaces the `AVAudioEngineCapture` scaffold; same `AudioCapturing` contract, coordinator unchanged). Injected: `MicrophoneAuthorizing` (real: `SystemMicrophoneAuthorization`, `AVCaptureDevice` audio TCC), `AudioInputSource` (real: `AudioEngineInput`), recordings directory (default `$TMPDIR/Yapper-Recordings/`).
- `AudioEngineInput`: fresh `AVAudioEngine` per session, tap on input bus 0 in the device's native format; 0 channels / 0 Hz -> `.noInputDevice`; `engine.start()` errors -> `.engineFailed(description)`.
- `RecordingFile`: one CAF per session (`recording-<UUID>.caf`), written from the tap thread under a `Mutex`; write errors are kept and reported by `finish()` as `.storageFailed`. Duration = frames / sample rate.
- Lifecycle guarantees (unit-tested with `FakeAudioInput`, generated buffers, temp directories): start requires `.authorized` and never prompts; start while capturing -> `.alreadyCapturing`; stop/cancel when idle -> `.notCapturing` / no-op; any start failure releases the input and deletes the file; stop always releases the input, and on write failure deletes the file; cancel releases and deletes; `discard` deletes only files this instance returned; leftover `recording-*.caf` from a crashed run are deleted on init. New error case: `AudioCaptureError.storageFailed(String)`.
- Tests: 15 lifecycle (`MicrophoneCaptureTests`), 5 file (`RecordingFileTests`), 1 permission mapping, 1 integration (`CapturedAudioTranscriptionTests`: synthesized speech converted to 48 kHz stereo Float32, delivered in 4096-frame chunks through capture, transcribed by the real SpeechAnalyzer from the temp CAF; no microphone).
- Hardware (opt-in, not run by automation): `MicrophoneHardwareTests` is skipped unless `TEST_RUNNER_YAPPER_MICROPHONE_TESTS=1` is set for `xcodebuild test` (env forwarding verified with a throwaway probe). It requests mic permission (prompt on first run), records ~1 s from the default input, and plays `say` through the speakers to check mic -> file -> transcript.

### Not verified / limitations
- `AudioEngineInput` and `SystemMicrophoneAuthorization.request()` have never run against real hardware/TCC. Needs the user-triggered hardware test plus a manual check in the signed app.
- Device changes mid-recording (`AVAudioEngineConfigurationChange`, unplugged/switched input) are not handled; the engine stops delivering and the partial recording is kept.
- Whether AVAudioEngine on macOS delivers silence or fails when permission is revoked mid-session is unknown; the permission check happens only at start.
- Files are plain CAF in `$TMPDIR` (not encrypted); privacy relies on immediate deletion and crash-leftover cleanup.

## Shortcut slice: hold fn (Globe) + Shift (implemented, test-first)
Replaces the earlier Carbon `RegisterEventHotKey` shortcut (control-option-command-F19). Carbon cannot fire on modifier-only combinations, so the user approved an event tap plus Input Monitoring. The Carbon registrar, mapping, validation, `DictationShortcut`, and their tests were deleted; no second shortcut path remains.

### Implementation
- `PushToTalkGesture` (pure): input is `ModifierSnapshot { function, shift }`. Both down -> `.pressed` once (either order); either up -> `.released` once; snapshots that do not change "both down" (e.g. command/option/control changing while held) emit nothing. `reset()` returns a pending `.released`.
- `ModifierTapMapping` (pure): tap config `eventsOfInterest = 1 << flagsChanged`, `.listenOnly`, `.cgSessionEventTap`, tail-append. `signal(type:flags:)`: `flagsChanged` -> snapshot of `maskSecondaryFn` + `maskShift` only; `tapDisabledByTimeout`/`tapDisabledByUserInput` -> `.disabled`; anything else -> nil.
- `ModifierEventTapping` (seam): `start(onEvent:)`, `reenable() -> Bool`, `currentModifiers()`, `stop()`. Real: `CoreGraphicsModifierTap` (`CGEvent.tapCreate`, run-loop source on the main run loop in common modes, callback hops in with `MainActor.assumeIsolated`, always returns the event unchanged; `stop()` disables, removes the source, invalidates the port; `isolated deinit` stops). `tapCreate` or run-loop-source failure -> `.eventTapUnavailable`. `currentModifiers()` reads `CGEventSource.flagsState(.combinedSessionState)` (modifier flags only).
- `InputMonitoringAuthorizing` (seam). Real: `SystemInputMonitoringAuthorization`: status from `IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)` (granted/denied/unknown -> authorized/denied/notDetermined; `CGPreflightListenEventAccess()` cannot tell "not asked" from "denied"); request via `CGRequestListenEventAccess()`.
- `PushToTalkMonitor: ShortcutMonitoring`: `start` throws `.permissionDenied` without touching the tap unless Input Monitoring is authorized; `requestPermission()` is the only path to the prompt. Ignores callbacks from a replaced/stopped tap (generation), emits the missing `.released` on stop/restart while held. On `.disabled`: re-enable, then resync from `currentModifiers()` (a release missed while disabled is emitted once); if re-enable fails: release if held, stop, report `.eventTapDisabled` via `onFailure`.
- `ShortcutError`: `.permissionDenied`, `.eventTapUnavailable`, `.eventTapDisabled`.
- `ShortcutEventDispatcher` unchanged: serializes events into `DictationCoordinator.handle(_:)`.
- AppShell: `start()` loads prefs, creates the dispatcher, then `refreshStatus()`. `refreshStatus()` reads Input Monitoring status and syncs the tap: installs it only after `start()`, before `stop()`, when authorized and not already running (also retries after a failure); removes it if the permission was revoked. `requestInputMonitoringAccess()` (menu button only) requests, then syncs. Exposes `isPushToTalkActive`, `shortcutError`, `inputMonitoringPermission`.
- Menu: Input Monitoring row (checking / allowed / "Allow Input Monitoring…" button with a privacy note / denied -> System Settings path and "quit and reopen"). Dictation section shows the hint "Hold fn (Globe) + Shift to dictate into the focused text field.", the error, or "off until Input Monitoring is allowed".
- Preferences: `AppPreferences` holds only `localeIdentifier`; older JSON with a `shortcut` key still decodes (unknown keys ignored, tested).
- Privacy: only `flagsChanged` is subscribed, so key-down/up events, key codes, and text never reach the app; only two bits are kept; nothing is logged or stored; events are never modified or suppressed (listen-only).

### Tests (no real tap, no permission prompt)
- 10 `PushToTalkGestureTests` cases, 16 `ModifierTapMappingTests` cases (incl. flagsChanged-only mask and listen-only options), 3 permission-mapping cases, 15 `PushToTalkMonitorTests` cases (permission gate, request only via intent, order, no duplicates, stop/restart pairing, stale callbacks, disable/re-enable/resync, re-enable failure), 2 `CoreGraphicsModifierTapTests` (construction/stop/re-enable never create a tap), AppComposition push-to-talk + Input Monitoring cases with the real monitor over `FakeModifierTap`/`FakeInputMonitoringAuthorization`.
- Mutation checks: removing the monitor permission guard, the post-re-enable resync, or the composition's started/stopped gate each fail their tests.
- The test host never builds the live composition (`LaunchEnvironment`), so no tap or TCC request happens during `xcodebuild test`.

### Not verified / limitations (manual)
- Never run against the real keyboard: tap creation, fn/Globe reporting `maskSecondaryFn` in `flagsChanged` on this Mac/keyboard (built-in vs external; third-party keyboards may not send fn), and whether callbacks arrive while Secure Input is on (password fields) are unverified.
- After granting Input Monitoring, macOS may require quitting and reopening Yapper before the tap delivers events or can be created; the menu says so. Real Fn+Shift behavior remains unverified.
- fn + Shift is not exclusive: the tap cannot suppress it, so macOS and apps still see it. Fn + Shift + arrow keys (select to line start/end, page) will also start dictation while held. The system Globe-key action ("Press 🌐 key to…") may fire on fn release; set it to "Do Nothing" if it interferes.
- Lost releases (sleep, fast user switching, tap disabled without a recoverable state) are mitigated by resync on re-enable and "Cancel Dictation"; no max recording duration.
- `.tapDisabledByUserInput` is re-enabled like a timeout; whether macOS keeps re-disabling it in some states is unverified (if re-enable fails the menu shows the error and the next menu open retries).

## TextInsertion slice (implemented, test-first)
### Mechanism (decided)
- Set `kAXSelectedTextAttribute` on the target app's focused element via `AXUIElementSetAttributeValue`. AppKit text controls implement it as "replace the selection, or insert at the caret" (`NSAccessibilityProtocol.accessibilitySelectedText` is read-write in the SDK, although the generic AX header comment says "Writable? No"). Per element, `AXUIElementIsAttributeSettable` is the authority: not settable means unsupported.
- Paste fallback (added after AI chat boxes in browsers/Electron did not accept AX insertion): `PasteAPI`, real `SystemPaste`. Used when the focused element has an `AXWebArea` ancestor (always, since web editors may silently ignore the AX set), when it is not settable, or when the AX call fails with `.noValue`/`.attributeUnsupported`/`.notImplemented`. Saves every pasteboard item/type, writes the transcript with nspasteboard.org Transient/Concealed/AutoGenerated markers, posts Cmd-V (`kVK_ANSI_V`, Command only, `.privateState` source, session tap), waits 500 ms, restores only if `changeCount` is unchanged. Refused (`.secureInputActive`) while `IsSecureEventInputEnabled()`. Limitations: non-QWERTY layouts that move V; a not-settable non-text focus (e.g. Finder desktop) gets a harmless Cmd-V and reports "Inserted"; clipboard managers that ignore the markers may record the transcript.
- Rejected: `CGEventKeyboardSetUnicodeString` typing (synthetic key events, layout/IME issues).
- Never read: the element's value, selected text, or any other text. Only `AXFocusedUIElement` (app element), `AXSubrole`, `AXRole`/`AXParent` of ancestors (web-content check), and settability are queried.
- Secure (password) fields (`AXSecureTextField` subrole) are always refused.
- Target = the app that is frontmost when dictation starts (`NSWorkspace.frontmostApplication`, excluding Yapper itself). At insert time the app must still be running and frontmost; the focused element is looked up fresh in that app (so moving focus to another field within the same app inserts there).
- Each AX element gets a 1 s messaging timeout so a hung target fails with `.cannotComplete` -> `.insertionFailed` instead of blocking the main actor for ~6 s.

### Implementation
- Seams: `AccessibilityAPI` (associated `Element`; real `SystemAccessibility` over `AXUIElement`) and `WorkspaceAPI` (real `SystemWorkspace` over `NSWorkspace`/`NSRunningApplication`). `AccessibilityTextInserter<AX>` holds the app-owned logic. Pure `AccessibilityErrorMapping`: `.apiDisabled` -> `.accessibilityPermissionDenied`, `.noValue` -> `.noFocusedElement`, `.attributeUnsupported`/`.notImplemented` -> `.unsupportedFocusedElement`, `.invalidUIElement` -> `.targetNoLongerFocused`, anything else -> `.insertionFailed`.
- New `TextInsertionError` cases: `.noFocusedElement`, `.unsupportedFocusedElement`.
- Permission: `AXIsProcessTrusted()` for status (no prompt); `AXIsProcessTrustedWithOptions(prompt: true)` only from `requestAccessibilityPermission()`, which only a menu button calls. macOS has no "not asked yet" state for Accessibility, so untrusted reports `.denied`.
- Order in `insert`: trust -> target running -> target frontmost -> focused element -> not secure -> settable -> set. Every failure before the set call has no side effect.
- Tests: 15 `AccessibilityTextInserterTests` + 8 mapping cases with `FakeAccessibility`/`FakeWorkspace`; 3 `SystemWorkspaceTests` against this process only. `SystemAccessibility` has no automated test: any real call needs Accessibility trust and another app's UI. Mutation check: removing the secure-field guard fails its test.

### Not verified / limitations (needs manual checks, see Manual verification)
- Never run against a real app. Unknown per app: whether the setter is honoured. Some apps (notably web content and Electron/Chromium, which may expose no AX tree unless `AXManualAccessibility`/`AXEnhancedUserInterface` is set, which Yapper deliberately does not touch) may report no focused element, report not settable, or accept the call and silently ignore it. A silent no-op cannot be detected without reading the field's text, which is out of policy, so it shows as "Inserted".
- Terminal-style views and custom-drawn editors are likely unsupported (typed error, nothing inserted).
- Signing comes from `Config/Signing.xcconfig`: ad-hoc by default, or an Apple Development identity from the gitignored `Config/Signing.local.xcconfig`. A real identity gives the app a stable designated requirement across rebuilds, so privacy grants survive; ad-hoc does not. Confirm with `codesign -dr - <app>`.
- A TCC Accessibility grant made to the old ad-hoc bundle may need one-time removal and re-granting for the signed Debug app. The menu now exposes **Refresh Permission Status** so the user can re-check after changing a permission in System Settings.
- Whether `AXIsProcessTrusted()` updates within an already-running process after changing Accessibility permission remains a manual check; quit and reopen the signed app if the status remains denied.
- AX calls are synchronous on the main actor (bounded by the 1 s timeout per call, a few calls per insertion).

## AppShell / StatusUI slice (implemented, test-first)
- `AppComposition` (`@Observable`, `@MainActor`): composition root plus app-level intents. `AppComposition.live()` builds `MicrophoneCapture`, `SpeechAnalyzerTranscriber`, `AccessibilityTextInserter(SystemAccessibility, SystemWorkspace)`, `PushToTalkMonitor(CoreGraphicsModifierTap, SystemInputMonitoringAuthorization)`, `UserDefaultsPreferencesStore`. Construction has no side effects beyond deleting crash-leftover recordings.
- `start()`: loads preferences or `AppPreferences.defaults(locale: .current)`, sets the coordinator locale, creates `ShortcutEventDispatcher { coordinator.handle }` (serialized, each event awaited), then `refreshStatus()`, which installs the fn + Shift tap only if Input Monitoring is granted (see Shortcut slice).
- `refreshStatus()`: Input Monitoring status (and tap sync), microphone status, Accessibility status, `transcriber.availability(for: locale)`. Never prompts, never downloads. Runs at start and whenever the menu appears (`.task`); the menu also has an explicit **Refresh Permission Status** button.
- `requestMicrophoneAccess()` / `requestAccessibilityAccess()` / `requestInputMonitoringAccess()`: the only paths to system prompts; called only from menu buttons.
- Model download, two user steps: `requestModelDownload()` (only when readiness is `.modelNotInstalled`) -> menu shows what will happen ("macOS will download this language's speech model from Apple; audio is never uploaded") -> `confirmModelDownload()` calls `prepare(for:)` once; `declineModelDownload()` cancels. States: `ModelInstallState` idle/awaitingConfirmation/installing/failed. Confirm without a pending request, a second confirm while installing, and requests when the model is ready/unsupported/unavailable are ignored.
- `stop()` (menu "Quit"): stops accepting shortcut events, removes the tap, waits for the dispatcher, cancels any active session. A held shortcut is abandoned, so quitting never inserts text.
- `cancelDictation()`: menu button while recording/transcribing; the mitigation for a lost key release.
- `LaunchEnvironment.isHostingTests`: the app binary is the unit-test host; when `XCTestConfigurationFilePath` is set, `AppDelegate` does not build or start the live composition, so `xcodebuild test` never installs the event tap or queries TCC/AX. Verified by a test running in the host process.
- `StatusPresentation` (pure): state titles, menu-bar symbols, actionable failure/shortcut-error/readiness messages, push-to-talk hint. `MenuBarContentView` (window-style `MenuBarExtra`) renders it and sends intents only.
- Preferences: `UserDefaultsPreferencesStore` stores JSON under key `preferences` (unreadable data -> nil -> defaults). Nothing is saved by the app yet (no settings UI). Tests use an in-memory `UserDefaults` subclass (a real suite leaves a plist in `~/Library/Preferences`).
- Push-to-talk gesture: hold fn (Globe) + Shift (fixed, not stored). The earlier default (control-option-command-F19 via Carbon) and its `defaults write` override are gone.
- Settings scene left as the existing placeholder; no new settings surface.
- Tests: `AppCompositionTests` (real `PushToTalkMonitor` + `FakeModifierTap`/`FakeInputMonitoringAuthorization`, fake capture/transcriber/inserter/preferences), 2 launch-environment, 6 `StatusPresentationTests` (parameterized), 5 preferences, 1 coordinator Accessibility pre-check. Mutation checks: removing the stop gate, or the confirmation guard, fails the corresponding tests.

### Not verified / limitations
- The app has not been launched by automation. Menu rendering, `.task` re-running on each menu open, and whether opening the window-style menu makes Yapper frontmost (which would make the next dictation fail with `.noInsertionTarget` until the user clicks back into the target app) are unverified.
- No maximum recording duration; a lost release is recovered only via "Cancel Dictation".
- After a microphone denial the user must change it in System Settings; the app shows the path but does not open Settings.
- The model download path (`prepare`) has never run (would download from Apple).

## Manual verification (user-driven; not run by the agent)
Build and run the signed Debug app:
```
cd ~/Desktop/Yapper
make run
```
Locale override (optional; quit first, relaunch after):
```
defaults write com.joshhatchard.Yapper preferences -data "$(printf '%s' '{"localeIdentifier":"en_AU"}' | xxd -p | tr -d '\n')"
# undo: defaults delete com.joshhatchard.Yapper preferences
```
Checklist:
0. Input Monitoring: menu shows "Push-to-talk (fn + Shift) is off…" and "Allow Input Monitoring…". Click it: macOS prompt; enable Yapper in System Settings › Privacy & Security › Input Monitoring; reopen the menu (quit and reopen if it still says off). Row turns to "Input Monitoring allowed" and the hint shows "Hold fn (Globe) + Shift…". Check typing in other apps is unaffected.
1. Menu-bar mic icon appears; menu shows "Ready", the push-to-talk hint, "Microphone" and "Accessibility" buttons, and "On-device speech model ready (English (Australia))".
2. "Allow Microphone Access…" shows the macOS prompt; allow; row turns to "Microphone allowed".
3. "Allow Accessibility Access…" opens the system permission flow; enable Yapper in System Settings › Privacy & Security › Accessibility; return to Yapper and click **Refresh Permission Status**. If it remains denied, quit and reopen the signed Debug app. If the old ad-hoc entry is stale, remove it and grant access to the signed Debug app at `~/Library/Developer/Xcode/DerivedData/Yapper-scaffold/Build/Products/Debug/Yapper.app`.
4. TextEdit (new document): hold fn + Shift (try both orders), speak, release either key. Icon goes mic.fill -> waveform -> mic; text appears at the caret; a selection is replaced; clipboard unchanged.
5. Repeat in Notes, Safari (address bar and a web text field), Mail, and one Electron/Chromium app (Slack/VS Code/Chrome). Record which insert, which show "not a text field Yapper can type into", and any that show "Inserted" but insert nothing (silent no-op).
6. Password field (Safari login or System Settings): must refuse, nothing inserted. Note whether fn + Shift fires at all under Secure Input.
7. Hold fn + Shift, Cmd-Tab to another app, release: "You switched apps…", nothing inserted.
8. Click a non-text area (Finder desktop) and dictate: a typed error, nothing inserted.
9. While holding fn + Shift, press/release Command or Option: no second recording starts. Release fn first, then Shift (and vice versa): one stop each. Built-in and external keyboard. Check the Globe-key system action does not interfere. "Cancel Dictation" recovers a stuck recording.
10. Rebuild and relaunch with `make run`: confirm the Apple Development designated requirement remains unchanged across builds. A one-time re-grant may be needed when moving from the previous ad-hoc build.
11. Quit via the menu while holding fn + Shift: nothing inserted.
12. Model download (only if you accept a download from Apple): with a supported, not-installed locale set via the `defaults write` above (e.g. `de_DE`), the menu offers "Download Speech Model…", asks for confirmation, and only "Download" starts it.
To re-test prompts: `tccutil reset Accessibility com.joshhatchard.Yapper`, `tccutil reset Microphone com.joshhatchard.Yapper`, `tccutil reset ListenEvent com.joshhatchard.Yapper` (Input Monitoring).
Opt-in hardware test (unchanged): `TEST_RUNNER_YAPPER_MICROPHONE_TESTS=1` before `xcodebuild test ...`. The Carbon shortcut opt-in test was removed with the Carbon path; the event tap has no automated hardware test.

## Decisions still to validate during scaffold/spikes
- Runtime on-device behavior of SpeechAnalyzer: offline operation with networking disabled, permission behaviour in a signed standalone app, model download UX.
- Physical-key behaviour of fn + Shift (fn reporting per keyboard, Secure Input, Globe-key action, fn + Shift + arrow overlap) and Input Monitoring grant/relaunch behaviour.
- Insertion mechanism remains the AX selected-text setter; per-app behavior needs the manual checks above. App Sandbox stays off because AX control of other apps is unavailable to sandboxed apps.
- Accessibility now uses a stable Apple Development signing identity across rebuilds. The old ad-hoc grant may need a one-time re-grant; future rebuilds should keep the same designated requirement.

## References
- Apple Speech framework, SFSpeechRecognizer: https://developer.apple.com/documentation/speech/sfspeechrecognizer
- Apple on-device capability: https://developer.apple.com/documentation/speech/sfspeechrecognizer/supportsondevicerecognition
- Apple SpeechAnalyzer: https://developer.apple.com/documentation/speech/speechanalyzer
- Apple AssetInventory: https://developer.apple.com/documentation/speech/assetinventory
- Apple CGEventFlags (`maskSecondaryFn`, `maskShift`): https://developer.apple.com/documentation/coregraphics/cgeventflags
- Apple CGEvent.tapCreate (listen-only taps): https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate%28tap%3Aplace%3Aoptions%3Aeventsofinterest%3Acallback%3Auserinfo%3A%29
- Apple CGRequestListenEventAccess: https://developer.apple.com/documentation/coregraphics/cgrequestlisteneventaccess%28%29

## Transcript modes (implemented, test-first)
- `TranscriptMode`: `.standard` (Default, raw transcript), `.ai` (clean prompt for an AI assistant), `.notes` (bullet notes). Picked with a segmented control in the menu; stored in `AppPreferences.transcriptMode` (missing/unknown decodes as `.standard`, locale kept).
- Formatting runs on-device only via Apple Foundation Models (`FoundationModelsFormatter`, `TranscriptFormatting` seam): fresh `LanguageModelSession` per transcript, greedy sampling, per-mode instructions in pure `FormattingInstructions`. The transcript is fenced (`<<<`/`>>>`) and the instructions say it is never addressed to the model, so dictated questions are rewritten, not answered.
- Coordinator: mode captured at `start()`; after a non-empty transcript, non-Default modes enter `.formatting` (active, cancellable). Any `FormattingError` (Apple Intelligence off, too long, guardrail, empty) inserts the raw transcript and ends in `.completedUnformatted(error)`, so nothing said is lost.
- Requires Apple Intelligence enabled (System Settings › Apple Intelligence & Siri); the menu shows why formatting is unavailable. Not verified against the real model: output quality, latency, and how often the model answers instead of rewriting.
- Hang fix (verified against the real model): a dictation the model wanted to answer ("what's the weather like today" in Notes) generated for 40 s+ with no output cap or timeout. Now: 10 s coordinator timeout (`.timedOut`, task cancelled, raw inserted), `maximumResponseTokens` = min(2000, 64 + 3 x words), transcripts under 4 words skip the model.
- Answer guard: few-shot examples, a "Do not reply" line in the prompt itself, and `looksLikeAnAnswer` (output > 2x + 80 chars, or < 75% of output words reused from the dictation) -> `.notARewrite`, raw inserted. Measured: rewrites 0.88-1.00 overlap, answers 0.00-0.67.
- Notes mode writes bullets only; there is no "Action items" section.
