import Foundation
import Testing

@testable import Yapper

@MainActor
@Suite("ShortcutEventDispatcher")
struct ShortcutEventDispatcherTests {
    @Test("each event is awaited before the next one starts")
    func eventsAreSerialized() async {
        let gate = Gate()
        var log: [String] = []
        let dispatcher = ShortcutEventDispatcher { event in
            log.append("begin \(event)")
            if event == .pressed { await gate.wait() }
            log.append("end \(event)")
        }

        dispatcher.enqueue(.pressed)
        await yieldUntil { !log.isEmpty }
        dispatcher.enqueue(.released)
        for _ in 0..<20 { await Task.yield() }
        #expect(log == ["begin pressed"])

        gate.open()
        await dispatcher.waitUntilIdle()
        #expect(log == ["begin pressed", "end pressed", "begin released", "end released"])
    }

    @Test("a release cancels a press that is still waiting in the queue")
    func queuedTapIsDropped() async {
        let gate = Gate()
        var handled: [ShortcutEvent] = []
        let dispatcher = ShortcutEventDispatcher { event in
            handled.append(event)
            if event == .released { await gate.wait() }  // first release stands in for a slow transcription
        }

        dispatcher.enqueue(.pressed)
        await yieldUntil { handled.count == 1 }
        dispatcher.enqueue(.released)
        await yieldUntil { handled.count == 2 }
        dispatcher.enqueue(.pressed)
        dispatcher.enqueue(.released)
        gate.open()
        await dispatcher.waitUntilIdle()

        #expect(handled == [.pressed, .released])
    }

    // MARK: - With the real coordinator

    let capture = FakeAudioCapture()
    let transcriber = FakeTranscriber()
    let inserter = FakeTextInserter()

    func makeCoordinator() -> DictationCoordinator {
        DictationCoordinator(
            audioCapture: capture, transcriber: transcriber, textInserter: inserter, formatter: FakeFormatter(),
            locale: Locale(identifier: "en_US"))
    }

    @Test("a release that arrives while the microphone is still starting finishes the session")
    func releaseDuringSlowStartIsKept() async {
        let gate = Gate()
        capture.startGate = gate
        let coordinator = makeCoordinator()
        let dispatcher = ShortcutEventDispatcher { await coordinator.handle($0) }

        dispatcher.enqueue(.pressed)
        await yieldUntil { capture.startCount == 1 }
        dispatcher.enqueue(.released)
        gate.open()
        await dispatcher.waitUntilIdle()

        #expect(coordinator.state == .completed)
        #expect(capture.stopCount == 1)
        #expect(inserter.insertions.map(\.text) == ["hello world"])
    }

    @Test("a tap during transcription does not start a second session afterwards")
    func tapDuringTranscriptionIsIgnored() async {
        transcriber.suspendsUntilResumed = true
        let coordinator = makeCoordinator()
        let dispatcher = ShortcutEventDispatcher { await coordinator.handle($0) }

        dispatcher.enqueue(.pressed)
        await yieldUntil { coordinator.state == .recording }
        dispatcher.enqueue(.released)
        await transcriber.waitUntilSuspended()
        dispatcher.enqueue(.pressed)
        dispatcher.enqueue(.released)
        transcriber.resume()
        await dispatcher.waitUntilIdle()

        #expect(coordinator.state == .completed)
        #expect(capture.startCount == 1)
        #expect(inserter.insertions.count == 1)
    }
}
