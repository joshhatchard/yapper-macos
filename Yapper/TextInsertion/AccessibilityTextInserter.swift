import ApplicationServices

/// Inserts text into the focused element of the target app.
///
/// Native text fields: sets the element's AX selected text, which replaces the selection or inserts
/// at the caret, with no clipboard use. Everywhere that does not work (web content in browsers and
/// Electron/Chromium apps, controls that do not accept AX text, focus the AX API cannot see) it
/// falls back to `PasteAPI`: pasteboard + Cmd-V, restoring the previous clipboard afterwards.
/// The target's text is never read: only the focused element's subrole, ancestor roles and
/// settability are queried. Password fields are always refused, and the paste fallback is refused
/// while macOS Secure Input is on.
@MainActor
final class AccessibilityTextInserter<AX: AccessibilityAPI>: TextInserting {
    private let accessibility: AX
    private let workspace: any WorkspaceAPI
    private let paster: any PasteAPI

    init(accessibility: AX, workspace: any WorkspaceAPI, paste: any PasteAPI) {
        self.accessibility = accessibility
        self.workspace = workspace
        self.paster = paste
    }

    /// macOS does not expose "not asked yet" for Accessibility, so untrusted reports `.denied`.
    func accessibilityStatus() -> PermissionStatus {
        accessibility.isProcessTrusted() ? .authorized : .denied
    }

    func requestAccessibilityPermission() {
        accessibility.requestTrust()
    }

    func currentTarget() -> InsertionTarget? {
        guard let frontmost = workspace.frontmostApplication(),
            frontmost.processIdentifier != workspace.ownProcessIdentifier
        else { return nil }
        return frontmost
    }

    /// Fails without side effects unless `target` is still running and frontmost. Order: trust ->
    /// running -> frontmost -> focused element -> not secure -> web content (paste) -> settable (else
    /// paste) -> set (unsupported: paste).
    func insert(_ text: String, into target: InsertionTarget) async throws(TextInsertionError) {
        guard accessibility.isProcessTrusted() else { throw .accessibilityPermissionDenied }
        guard workspace.isRunning(target.processIdentifier) else { throw .targetTerminated }
        guard workspace.frontmostApplication()?.processIdentifier == target.processIdentifier else {
            throw .targetNoLongerFocused
        }

        let element: AX.Element
        do {
            element = try accessibility.focusedElement(ofApplication: target.processIdentifier)
        } catch {
            try await pasteIfFallbackAllowed(text, after: error)
            return
        }
        guard accessibility.subrole(of: element) != kAXSecureTextFieldSubrole else { throw .unsupportedFocusedElement }
        if accessibility.isInWebContent(element) {
            try await paste(text)
            return
        }

        let settable: Bool
        do {
            settable = try accessibility.isSelectedTextSettable(element)
        } catch {
            try await pasteIfFallbackAllowed(text, after: error)
            return
        }
        guard settable else {
            try await paste(text)
            return
        }

        do {
            try accessibility.setSelectedText(text, on: element)
        } catch {
            try await pasteIfFallbackAllowed(text, after: error)
        }
    }

    /// Pastes when the AX failure only means "AX cannot do this here"; rethrows anything else
    /// (permission, focus moved, hung app) as the mapped error.
    private func pasteIfFallbackAllowed(_ text: String, after error: AXCallError) async throws(TextInsertionError) {
        let mapped = AccessibilityErrorMapping.error(for: error.code)
        switch mapped {
        case .noFocusedElement, .unsupportedFocusedElement:
            try await paste(text)
        default:
            throw mapped
        }
    }

    private func paste(_ text: String) async throws(TextInsertionError) {
        guard !paster.isSecureInputActive else { throw .secureInputActive }
        do {
            try await paster.paste(text)
        } catch {
            throw .insertionFailed
        }
    }
}
