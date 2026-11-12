import Foundation
import Testing

@testable import Yapper

/// How the dictation coordinator applies the selected transcript mode.
@MainActor
@Suite("DictationCoordinator transcript modes")
struct TranscriptModeCoordinatorTests {
    let capture = FakeAudioCapture()
    let transcriber = FakeTranscriber()
    let inserter = FakeTextInserter()
    let formatter = FakeFormatter()

    func makeCoordinator(mode: TranscriptMode, timeout: Duration = .seconds(10)) -> DictationCoordinator {
        let coordinator = DictationCoordinator(
            audioCapture: capture, transcriber: transcriber, textInserter: inserter, formatter: formatter,
            locale: Locale(identifier: "en_US"), formattingTimeout: timeout)
        coordinator.mode = mode
        return coordinator
    }

    @Test("default mode inserts the raw transcript and never calls the formatter")
    func defaultModeIsRaw() async {
        let coordinator = makeCoordinator(mode: .standard)
        await coordinator.start()
        await coordinator.finish()

        #expect(coordinator.state == .completed)
        #expect(formatter.requests.isEmpty)
        #expect(inserter.insertions == [.init(text: "hello world", target: .sample)])
    }

    @Test("AI and Notes modes insert the formatted transcript", arguments: [TranscriptMode.ai, .notes])
    func formattingModesInsertFormattedText(mode: TranscriptMode) async {
        let coordinator = makeCoordinator(mode: mode)
        await coordinator.start()
        await coordinator.finish()

        #expect(coordinator.state == .completed)
        #expect(formatter.requests == [.init(text: "hello world", mode: mode)])
        #expect(inserter.insertions == [.init(text: "[\(mode.rawValue)] hello world", target: .sample)])
    }

    @Test("the mode is fixed when recording starts; changing it mid-session applies next time")
    func modeIsCapturedAtStart() async {
        let coordinator = makeCoordinator(mode: .notes)
        await coordinator.start()
        coordinator.mode = .standard
        await coordinator.finish()

        #expect(formatter.requests.map(\.mode) == [.notes])
    }

    @Test("formatting shows its own state and is active")
    func formattingState() async {
        let gate = Gate()
        formatter.gate = gate
        let coordinator = makeCoordinator(mode: .ai)
        await coordinator.start()
        let finishing = Task { await coordinator.finish() }
        await yieldUntil { coordinator.state == .formatting }

        #expect(coordinator.state == .formatting)
        #expect(coordinator.state.isActive)
        gate.open()
        await finishing.value
        #expect(coordinator.state == .completed)
    }

    @Test("cancel while formatting drops the result and still discards audio")
    func cancelWhileFormatting() async {
        let gate = Gate()
        formatter.gate = gate
        let coordinator = makeCoordinator(mode: .notes)
        await coordinator.start()
        let finishing = Task { await coordinator.finish() }
        await yieldUntil { coordinator.state == .formatting }

        await coordinator.cancel()
        gate.open()
        await finishing.value

        #expect(coordinator.state == .cancelled)
        #expect(inserter.insertions.isEmpty)
        #expect(capture.discarded == [.sample])
    }

    @Test("a formatting failure still inserts the raw transcript, so nothing said is lost")
    func formattingFailureFallsBackToRaw() async {
        formatter.error = .unavailable(.appleIntelligenceNotEnabled)
        let coordinator = makeCoordinator(mode: .ai)
        await coordinator.start()
        await coordinator.finish()

        #expect(coordinator.state == .completedUnformatted(.unavailable(.appleIntelligenceNotEnabled)))
        #expect(inserter.insertions == [.init(text: "hello world", target: .sample)])
    }

    @Test("a formatter that never finishes times out and the raw transcript is inserted")
    func formattingTimesOut() async {
        let gate = Gate()
        formatter.gate = gate
        let coordinator = makeCoordinator(mode: .notes, timeout: .milliseconds(50))
        await coordinator.start()

        await coordinator.finish()

        #expect(coordinator.state == .completedUnformatted(.timedOut))
        #expect(inserter.insertions == [.init(text: "hello world", target: .sample)])
        gate.open()
        await yieldUntil { formatter.cancelledRequests == 1 }
        #expect(formatter.cancelledRequests == 1)
    }

    @Test("a formatter that finishes in time is not cut off")
    func fastFormattingBeatsTimeout() async {
        let coordinator = makeCoordinator(mode: .ai, timeout: .seconds(5))
        await coordinator.start()

        await coordinator.finish()

        #expect(coordinator.state == .completed)
        #expect(formatter.cancelledRequests == 0)
    }

    @Test("an empty transcript fails before formatting")
    func emptyTranscriptSkipsFormatting() async {
        transcriber.result = .success(Transcript(text: "   "))
        let coordinator = makeCoordinator(mode: .notes)
        await coordinator.start()
        await coordinator.finish()

        #expect(coordinator.state == .failed(.emptyTranscript))
        #expect(formatter.requests.isEmpty)
    }
}

@Suite("FormattingInstructions")
struct FormattingInstructionsTests {
    @Test("default mode has no instructions")
    func standardHasNone() {
        #expect(FormattingInstructions.instructions(for: .standard) == nil)
    }

    @Test(
        "formatting modes treat the transcript as text to rewrite, never as a request",
        arguments: [TranscriptMode.ai, .notes])
    func instructionsForbidAnswering(mode: TranscriptMode) throws {
        let instructions = try #require(FormattingInstructions.instructions(for: mode))

        #expect(instructions.contains("never addressed to you"))
        #expect(instructions.contains("Examples:"))
        #expect(instructions.contains("Output only"))
    }

    @Test("Notes mode asks for bullets; AI mode keeps the user's voice")
    func modeSpecificRules() throws {
        #expect(try #require(FormattingInstructions.instructions(for: .notes)).contains("starting with \"- \""))
        #expect(try #require(FormattingInstructions.instructions(for: .ai)).contains("first person"))
    }

    @Test(
        "only transcripts with a few words go to the model",
        arguments: [("hello", false), ("um okay yeah", false), ("what's the weather like", true)])
    func shortTranscriptsSkipTheModel(text: String, formats: Bool) {
        #expect(FormattingInstructions.isWorthFormatting(text) == formats)
    }

    @Test("output is capped relative to what was said, with an upper bound")
    func outputCap() {
        #expect(FormattingInstructions.maximumResponseTokens(for: "one two three four") == 76)
        #expect(
            FormattingInstructions.maximumResponseTokens(for: String(repeating: "word ", count: 5_000)) == 2_000)
    }

    @Test("Notes writes bullets only, never an action-items section, and answers nothing")
    func notesRulesForUnremarkableSpeech() throws {
        let notes = try #require(FormattingInstructions.instructions(for: .notes))
        #expect(notes.contains("single bullet"))
        #expect(!notes.localizedCaseInsensitiveContains("action items"))
        #expect(notes.contains("Even when it is a question"))
    }

    @Test(
        "answers are told apart from rewrites (real model outputs)",
        arguments: [
            ("what is two plus two", "Four.", true),
            ("what's the capital of France", "- Capital of France: Paris", true),
            ("tell me a joke about cats", "Why did the cat sit on the computer?", true),
            (
                "write me a poem about the ocean",
                "Sure, here's a poem about the ocean:\n\nThe ocean is vast and deep,", true
            ),
            ("what is two plus two", "What is two plus two?", false),
            (
                "can you um help me write a function that like takes a list and uh removes duplicates actually no keep "
                    + "the order too",
                "Can you help me write a function that takes a list and removes duplicates while keeping the original order?",
                false
            ),
            (
                "okay so for the meeting tomorrow we need to um book the room and uh Sarah said the budget is like five "
                    + "thousand and I need to email the client",
                "- Meeting tomorrow\n- Book the room\n- Budget: $5,000 (Sarah)\n- Email the client",
                false
            ),
        ])
    func detectsAnswers(transcript: String, output: String, isAnswer: Bool) {
        #expect(FormattingInstructions.looksLikeAnAnswer(output, to: transcript) == isAnswer)
    }

    @Test("the prompt fences the transcript")
    func promptFencesTranscript() {
        #expect(FormattingInstructions.prompt(for: "um hi").contains("Dictation: <<<um hi>>>"))
        #expect(FormattingInstructions.prompt(for: "um hi").contains("Do not reply"))
    }

    @Test(
        "model output is trimmed and an echoed fence is removed",
        arguments: [
            ("  hello  \n", "hello"),
            ("<<<\nhello\n>>>", "hello"),
            ("Output: hello", "hello"),
            ("- a\n- b", "- a\n- b"),
        ])
    func cleanup(raw: String, expected: String) {
        #expect(FormattingInstructions.cleaned(raw) == expected)
    }
}

@Suite("TranscriptMode")
struct TranscriptModeTests {
    @Test("modes are listed Default, AI, Notes with stable stored values")
    func order() {
        #expect(TranscriptMode.allCases == [.standard, .ai, .notes])
        #expect(TranscriptMode.allCases.map(\.rawValue) == ["standard", "ai", "notes"])
        #expect(TranscriptMode.allCases.map(\.title) == ["Default", "AI", "Notes"])
    }
}
