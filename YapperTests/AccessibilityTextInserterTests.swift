import ApplicationServices
import Testing

@testable import Yapper

@MainActor
@Suite("AccessibilityTextInserter")
struct AccessibilityTextInserterTests {
    let accessibility = FakeAccessibility()
    let workspace = FakeWorkspace()
    let paste = FakePaste()

    func makeInserter() -> AccessibilityTextInserter<FakeAccessibility> {
        AccessibilityTextInserter(accessibility: accessibility, workspace: workspace, paste: paste)
    }

    @Test("status is authorized only when the process is trusted")
    func statusReflectsTrust() {
        let inserter = makeInserter()
        #expect(inserter.accessibilityStatus() == .authorized)

        accessibility.trusted = false
        #expect(inserter.accessibilityStatus() == .denied)
    }

    @Test("requesting permission asks the system once and nothing else")
    func requestForwardsToSystemPrompt() {
        makeInserter().requestAccessibilityPermission()

        #expect(accessibility.trustRequests == 1)
    }

    @Test("status never prompts")
    func statusDoesNotPrompt() {
        _ = makeInserter().accessibilityStatus()

        #expect(accessibility.trustRequests == 0)
    }

    @Test("current target is the frontmost app")
    func currentTargetIsFrontmost() {
        workspace.frontmost = .other

        #expect(makeInserter().currentTarget() == .other)
    }

    @Test("this app is never a target")
    func ownAppIsNotATarget() {
        workspace.frontmost = InsertionTarget(processIdentifier: workspace.ownProcessIdentifier, bundleIdentifier: nil)

        #expect(makeInserter().currentTarget() == nil)
    }

    @Test("no frontmost app means no target")
    func noFrontmostApp() {
        workspace.frontmost = nil

        #expect(makeInserter().currentTarget() == nil)
    }

    @Test("insert sets the selected text of the target's focused element")
    func insertSetsSelectedText() async throws {
        accessibility.focus(7, in: .sample)

        try await makeInserter().insert("hello world", into: .sample)

        #expect(accessibility.setCalls.map(\.text) == ["hello world"])
        #expect(accessibility.setCalls.map(\.element) == [7])
        #expect(paste.pastes.isEmpty)
    }

    @Test("insert without Accessibility trust fails before touching the target")
    func insertRequiresTrust() async {
        accessibility.trusted = false
        accessibility.focus(7, in: .sample)

        await #expect(throws: TextInsertionError.accessibilityPermissionDenied) {
            try await makeInserter().insert("hi", into: .sample)
        }
        #expect(accessibility.setCalls.isEmpty)
    }

    @Test("insert into a quit app fails with targetTerminated")
    func insertIntoTerminatedApp() async {
        workspace.running.remove(InsertionTarget.sample.processIdentifier)
        accessibility.focus(7, in: .sample)

        await #expect(throws: TextInsertionError.targetTerminated) {
            try await makeInserter().insert("hi", into: .sample)
        }
        #expect(accessibility.setCalls.isEmpty)
    }

    @Test("insert fails when another app became frontmost since dictation started")
    func insertRequiresTargetStillFrontmost() async {
        workspace.frontmost = .other
        accessibility.focus(7, in: .sample)
        accessibility.focus(8, in: .other)

        await #expect(throws: TextInsertionError.targetNoLongerFocused) {
            try await makeInserter().insert("hi", into: .sample)
        }
        #expect(accessibility.setCalls.isEmpty)
    }

    @Test("a focused element that does not accept AX text is pasted into instead")
    func notSettableFallsBackToPaste() async throws {
        accessibility.focus(7, in: .sample)
        accessibility.settable[7] = .success(false)

        try await makeInserter().insert("hi", into: .sample)

        #expect(accessibility.setCalls.isEmpty)
        #expect(paste.pastes == ["hi"])
    }

    @Test("dictation is never inserted into a secure (password) field")
    func secureFieldIsUnsupported() async {
        accessibility.focus(7, in: .sample)
        accessibility.subroles[7] = "AXSecureTextField"

        await #expect(throws: TextInsertionError.unsupportedFocusedElement) {
            try await makeInserter().insert("hi", into: .sample)
        }
        #expect(accessibility.setCalls.isEmpty)
        #expect(paste.pastes.isEmpty)
    }

    @Test("a secure field inside web content is refused, not pasted into")
    func secureWebFieldIsUnsupported() async {
        accessibility.focus(7, in: .sample)
        accessibility.subroles[7] = "AXSecureTextField"
        accessibility.webContent = [7]

        await #expect(throws: TextInsertionError.unsupportedFocusedElement) {
            try await makeInserter().insert("hi", into: .sample)
        }
        #expect(paste.pastes.isEmpty)
    }

    @Test("web content (browsers, Electron) is always pasted into, even when AX claims settable")
    func webContentIsPasted() async throws {
        accessibility.focus(7, in: .sample)
        accessibility.webContent = [7]

        try await makeInserter().insert("hello", into: .sample)

        #expect(accessibility.setCalls.isEmpty)
        #expect(paste.pastes == ["hello"])
    }

    @Test(
        "focus the AX API cannot see falls back to paste",
        arguments: [AXError.noValue, .attributeUnsupported, .notImplemented])
    func invisibleFocusFallsBackToPaste(code: AXError) async throws {
        accessibility.focused[InsertionTarget.sample.processIdentifier] = .failure(AXCallError(code: code))

        try await makeInserter().insert("hi", into: .sample)

        #expect(paste.pastes == ["hi"])
    }

    @Test("other focused-element failures are mapped and nothing is pasted")
    func focusFailureIsMapped() async {
        accessibility.focused[InsertionTarget.sample.processIdentifier] = .failure(AXCallError(code: .cannotComplete))

        await #expect(throws: TextInsertionError.insertionFailed) {
            try await makeInserter().insert("hi", into: .sample)
        }
        #expect(paste.pastes.isEmpty)
    }

    @Test("an unsupported settability query falls back to paste")
    func unsupportedSettabilityFallsBackToPaste() async throws {
        accessibility.focus(7, in: .sample)
        accessibility.settable[7] = .failure(AXCallError(code: .attributeUnsupported))

        try await makeInserter().insert("hi", into: .sample)

        #expect(accessibility.setCalls.isEmpty)
        #expect(paste.pastes == ["hi"])
    }

    @Test("other settability failures are mapped, not treated as settable or pasted")
    func settabilityErrorIsMapped() async {
        accessibility.focus(7, in: .sample)
        accessibility.settable[7] = .failure(AXCallError(code: .invalidUIElement))

        await #expect(throws: TextInsertionError.targetNoLongerFocused) {
            try await makeInserter().insert("hi", into: .sample)
        }
        #expect(accessibility.setCalls.isEmpty)
        #expect(paste.pastes.isEmpty)
    }

    @Test("an unsupported set call falls back to paste")
    func unsupportedSetFallsBackToPaste() async throws {
        accessibility.focus(7, in: .sample)
        accessibility.setError = AXCallError(code: .attributeUnsupported)

        try await makeInserter().insert("hi", into: .sample)

        #expect(paste.pastes == ["hi"])
    }

    @Test("a failing set call is mapped")
    func setErrorIsMapped() async {
        accessibility.focus(7, in: .sample)
        accessibility.setError = AXCallError(code: .invalidUIElement)

        await #expect(throws: TextInsertionError.targetNoLongerFocused) {
            try await makeInserter().insert("hi", into: .sample)
        }
        #expect(paste.pastes.isEmpty)
    }

    @Test("paste is refused while macOS Secure Input is on (a password field has the keyboard)")
    func secureInputBlocksPaste() async {
        accessibility.focus(7, in: .sample)
        accessibility.webContent = [7]
        paste.secureInputActive = true

        await #expect(throws: TextInsertionError.secureInputActive) {
            try await makeInserter().insert("hi", into: .sample)
        }
        #expect(paste.pastes.isEmpty)
    }

    @Test("Secure Input does not block direct AX insertion into a normal native field")
    func secureInputAllowsAXSet() async throws {
        accessibility.focus(7, in: .sample)
        paste.secureInputActive = true

        try await makeInserter().insert("hi", into: .sample)

        #expect(accessibility.setCalls.map(\.text) == ["hi"])
    }

    @Test("a failing paste is reported as insertionFailed")
    func pasteFailureIsMapped() async {
        accessibility.focus(7, in: .sample)
        accessibility.webContent = [7]
        paste.error = .keystrokeFailed

        await #expect(throws: TextInsertionError.insertionFailed) {
            try await makeInserter().insert("hi", into: .sample)
        }
    }
}
