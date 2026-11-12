import ApplicationServices

@testable import Yapper

/// Stands in for the AX API. Elements are plain integers; nothing touches other apps.
@MainActor
final class FakeAccessibility: AccessibilityAPI {
    typealias Element = Int

    var trusted = true
    var focused: [pid_t: Result<Int, AXCallError>] = [:]
    var subroles: [Int: String] = [:]
    var settable: [Int: Result<Bool, AXCallError>] = [:]
    var setError: AXCallError?
    /// Elements that sit inside web content (an `AXWebArea`).
    var webContent: Set<Int> = []

    private(set) var trustRequests = 0
    private(set) var setCalls: [(text: String, element: Int)] = []

    func isProcessTrusted() -> Bool { trusted }
    func requestTrust() { trustRequests += 1 }

    func focusedElement(ofApplication processIdentifier: pid_t) throws(AXCallError) -> Int {
        try (focused[processIdentifier] ?? .failure(AXCallError(code: .noValue))).get()
    }

    func subrole(of element: Int) -> String? { subroles[element] }

    func isInWebContent(_ element: Int) -> Bool { webContent.contains(element) }

    func isSelectedTextSettable(_ element: Int) throws(AXCallError) -> Bool {
        try (settable[element] ?? .success(true)).get()
    }

    func setSelectedText(_ text: String, on element: Int) throws(AXCallError) {
        if let setError { throw setError }
        setCalls.append((text, element))
    }

    /// Makes `element` the focused, editable element of `target`.
    func focus(_ element: Int, in target: InsertionTarget) {
        focused[target.processIdentifier] = .success(element)
    }
}

/// Stands in for NSWorkspace / NSRunningApplication.
@MainActor
final class FakeWorkspace: WorkspaceAPI {
    var frontmost: InsertionTarget? = .sample
    var running: Set<pid_t> = [InsertionTarget.sample.processIdentifier, InsertionTarget.other.processIdentifier]
    let ownProcessIdentifier: pid_t = 999

    func frontmostApplication() -> InsertionTarget? { frontmost }
    func isRunning(_ processIdentifier: pid_t) -> Bool { running.contains(processIdentifier) }
}

/// Stands in for the pasteboard + Cmd-V fallback. Never touches the real pasteboard or posts keys.
@MainActor
final class FakePaste: PasteAPI {
    var secureInputActive = false
    var error: PasteError?
    private(set) var pastes: [String] = []

    var isSecureInputActive: Bool { secureInputActive }

    func paste(_ text: String) async throws(PasteError) {
        if let error { throw error }
        pastes.append(text)
    }
}
