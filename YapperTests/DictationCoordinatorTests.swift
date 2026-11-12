import Foundation
import Testing

@testable import Yapper

@MainActor
@Suite("DictationCoordinator")
struct DictationCoordinatorTests {
    let capture = FakeAudioCapture()
    let transcriber = FakeTranscriber()
    let inserter = FakeTextInserter()
    let formatter = FakeFormatter()

    func makeCoordinator(mode: TranscriptMode = .standard) -> DictationCoordinator {
        let coordinator = DictationCoordinator(
            audioCapture: capture,
            transcriber: transcriber,
            textInserter: inserter,
            formatter: formatter,
            locale: Locale(identifier: "en_US")
        )
        coordinator.mode = mode
        return coordinator
    }

    @Test("start without Accessibility fails before the microphone opens")
    func startRequiresAccessibility() async {
        inserter.accessibility = .denied
        let coordinator = makeCoordinator()

        await coordinator.start()

        #expect(coordinator.state == .failed(.textInsertion(.accessibilityPermissionDenied)))
        #expect(capture.startCount == 0)
        #expect(inserter.permissionRequests == 0)
    }

    @Test("start begins capture and enters recording")
    func startBeginsRecording() async {
        let coordinator = makeCoordinator()

        await coordinator.start()

        #expect(coordinator.state == .recording)
        #expect(capture.startCount == 1)
    }

    @Test("finish inserts transcript into the target that was focused at start")
    func finishInsertsIntoOriginalTarget() async {
        let coordinator = makeCoordinator()
        await coordinator.start()
        inserter.target = .other

        await coordinator.finish()

        #expect(coordinator.state == .completed)
        #expect(transcriber.transcribed == [.sample])
        #expect(inserter.insertions == [.init(text: "hello world", target: .sample)])
    }

    @Test("finish discards captured audio after successful insertion")
    func finishDiscardsAudioOnSuccess() async {
        let coordinator = makeCoordinator()
        await coordinator.start()

        await coordinator.finish()

        #expect(capture.discarded == [.sample])
    }

    @Test("transcription failure ends in a typed failure without inserting")
    func transcriptionFailureFails() async {
        transcriber.result = .failure(.recognitionFailed("model error"))
        let coordinator = makeCoordinator()
        await coordinator.start()

        await coordinator.finish()

        #expect(coordinator.state == .failed(.transcription(.recognitionFailed("model error"))))
        #expect(inserter.insertions.isEmpty)
    }

    @Test("transcription failure still discards captured audio")
    func transcriptionFailureDiscardsAudio() async {
        transcriber.result = .failure(.modelUnavailable(Locale(identifier: "en_US")))
        let coordinator = makeCoordinator()
        await coordinator.start()

        await coordinator.finish()

        #expect(capture.discarded == [.sample])
    }

    @Test("insertion failure ends in a typed failure")
    func insertionFailureFails() async {
        inserter.insertError = .targetNoLongerFocused
        let coordinator = makeCoordinator()
        await coordinator.start()

        await coordinator.finish()

        #expect(coordinator.state == .failed(.textInsertion(.targetNoLongerFocused)))
    }

    @Test("whitespace-only transcript fails as empty without inserting")
    func emptyTranscriptFails() async {
        transcriber.result = .success(Transcript(text: " \n\t "))
        let coordinator = makeCoordinator()
        await coordinator.start()

        await coordinator.finish()

        #expect(coordinator.state == .failed(.emptyTranscript))
        #expect(inserter.insertions.isEmpty)
    }

    @Test("capture start failure ends in a typed failure instead of recording")
    func captureStartFailureFails() async {
        capture.startError = .permissionDenied
        let coordinator = makeCoordinator()

        await coordinator.start()

        #expect(coordinator.state == .failed(.audioCapture(.permissionDenied)))
    }

    @Test("start without an insertion target fails without opening the microphone")
    func startWithoutTargetFails() async {
        inserter.target = nil
        let coordinator = makeCoordinator()

        await coordinator.start()

        #expect(coordinator.state == .failed(.noInsertionTarget))
        #expect(capture.startCount == 0)
    }

    @Test("stop capture failure ends in a typed failure without transcribing")
    func stopCaptureFailureFails() async {
        capture.stopResult = .failure(.engineFailed("device lost"))
        let coordinator = makeCoordinator()
        await coordinator.start()

        await coordinator.finish()

        #expect(coordinator.state == .failed(.audioCapture(.engineFailed("device lost"))))
        #expect(transcriber.transcribed.isEmpty)
    }

    @Test("cancel while recording releases capture and ends cancelled")
    func cancelWhileRecording() async {
        let coordinator = makeCoordinator()
        await coordinator.start()

        await coordinator.cancel()

        #expect(coordinator.state == .cancelled)
        #expect(capture.cancelCount == 1)
    }

    @Test("finish after cancel is ignored")
    func finishAfterCancelIsIgnored() async {
        let coordinator = makeCoordinator()
        await coordinator.start()
        await coordinator.cancel()

        await coordinator.finish()

        #expect(coordinator.state == .cancelled)
        #expect(capture.stopCount == 0)
        #expect(transcriber.transcribed.isEmpty)
    }

    @Test("start while already recording is ignored")
    func repeatedStartIsIgnored() async {
        let coordinator = makeCoordinator()
        await coordinator.start()

        await coordinator.start()

        #expect(coordinator.state == .recording)
        #expect(capture.startCount == 1)
    }

    @Test("start while transcribing is ignored")
    func startWhileTranscribingIsIgnored() async {
        transcriber.suspendsUntilResumed = true
        let coordinator = makeCoordinator()
        await coordinator.start()
        let finishing = Task { await coordinator.finish() }
        await transcriber.waitUntilSuspended()

        await coordinator.start()

        #expect(coordinator.state == .transcribing)
        #expect(capture.startCount == 1)
        transcriber.resume()
        await finishing.value
    }

    @Test("cancel while transcribing drops the result and still discards audio")
    func cancelWhileTranscribing() async {
        transcriber.suspendsUntilResumed = true
        let coordinator = makeCoordinator()
        await coordinator.start()
        let finishing = Task { await coordinator.finish() }
        await transcriber.waitUntilSuspended()

        await coordinator.cancel()
        transcriber.resume()
        await finishing.value

        #expect(coordinator.state == .cancelled)
        #expect(inserter.insertions.isEmpty)
        #expect(capture.discarded == [.sample])
    }

    @Test("transcription error after cancel keeps the session cancelled")
    func transcriptionErrorAfterCancelStaysCancelled() async {
        transcriber.suspendsUntilResumed = true
        transcriber.result = .failure(.cancelled)
        let coordinator = makeCoordinator()
        await coordinator.start()
        let finishing = Task { await coordinator.finish() }
        await transcriber.waitUntilSuspended()

        await coordinator.cancel()
        transcriber.resume()
        await finishing.value

        #expect(coordinator.state == .cancelled)
    }

    @Test("cancel with no active session leaves the last outcome untouched")
    func cancelWhenInactiveIsIgnored() async {
        let coordinator = makeCoordinator()
        await coordinator.start()
        await coordinator.finish()

        await coordinator.cancel()

        #expect(coordinator.state == .completed)
        #expect(capture.cancelCount == 0)
    }

    @Test("a new session can start and complete after a failure")
    func recoversAfterFailure() async {
        transcriber.result = .failure(.recognitionFailed("model error"))
        let coordinator = makeCoordinator()
        await coordinator.start()
        await coordinator.finish()
        transcriber.result = .success(Transcript(text: "second try"))

        await coordinator.start()
        await coordinator.finish()

        #expect(coordinator.state == .completed)
        #expect(inserter.insertions == [.init(text: "second try", target: .sample)])
    }

    @Test("shortcut press records and release inserts the transcript")
    func shortcutEventsDriveSession() async {
        let coordinator = makeCoordinator()

        await coordinator.handle(.pressed)
        #expect(coordinator.state == .recording)

        await coordinator.handle(.released)
        #expect(coordinator.state == .completed)
        #expect(inserter.insertions == [.init(text: "hello world", target: .sample)])
    }
}
