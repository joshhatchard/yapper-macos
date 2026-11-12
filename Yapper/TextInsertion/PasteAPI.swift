/// Seam over the pasteboard + Cmd-V fallback used where direct AX insertion does not work (web
/// content, Electron/Chromium editors, controls without AX text support). Real: `SystemPaste`.
@MainActor
protocol PasteAPI: AnyObject {
    /// True while macOS Secure Input is on (a password field somewhere has the keyboard). Pasting is
    /// refused then, so dictation never lands in a password field the AX API could not see.
    var isSecureInputActive: Bool { get }
    /// Puts `text` on the pasteboard, sends Cmd-V to the frontmost app, then restores the previous
    /// pasteboard contents unless something else was copied meanwhile.
    func paste(_ text: String) async throws(PasteError)
}

enum PasteError: Error, Equatable, Sendable {
    case pasteboardWriteFailed
    case keystrokeFailed
}
