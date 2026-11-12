import AppKit
import Testing

@testable import Yapper

/// Runs against a private, uniquely named pasteboard with a fake keystroke: the user's clipboard is
/// never read or changed and no key events are posted.
@MainActor
@Suite("SystemPaste")
struct SystemPasteTests {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("YapperTests-\(UUID().uuidString)"))

    /// Records what the pasteboard held at the moment Cmd-V would have been pressed.
    final class KeystrokeProbe {
        var seen: [String?] = []
        var markers: [Bool] = []
        var error: PasteError?
        var copyDuringPaste: String?
    }

    func makePaste(_ probe: KeystrokeProbe) -> SystemPaste {
        let board = pasteboard
        return SystemPaste(
            pasteboard: board,
            restoreDelay: .zero,
            postKeystroke: { () throws(PasteError) in
                probe.seen.append(board.string(forType: .string))
                probe.markers.append(board.types?.contains(SystemPaste.transientType) ?? false)
                if let error = probe.error { throw error }
                if let copy = probe.copyDuringPaste {
                    board.clearContents()
                    board.setString(copy, forType: .string)
                }
            },
            isSecureInputActive: { false })
    }

    @Test("the transcript is on the pasteboard, marked transient, when Cmd-V is sent")
    func transcriptIsOnPasteboardDuringKeystroke() async throws {
        let probe = KeystrokeProbe()

        try await makePaste(probe).paste("hello world")

        #expect(probe.seen == ["hello world"])
        #expect(probe.markers == [true])
    }

    @Test("the previous clipboard contents, including every type, are restored")
    func previousContentsAreRestored() async throws {
        let custom = NSPasteboard.PasteboardType("com.example.custom")
        let item = NSPasteboardItem()
        item.setString("original", forType: .string)
        item.setData(Data([1, 2, 3]), forType: custom)
        pasteboard.clearContents()
        pasteboard.writeObjects([item])

        try await makePaste(KeystrokeProbe()).paste("dictated")

        #expect(pasteboard.string(forType: .string) == "original")
        #expect(pasteboard.data(forType: custom) == Data([1, 2, 3]))
        #expect(pasteboard.types?.contains(SystemPaste.transientType) == false)
    }

    @Test("an empty clipboard is left empty")
    func emptyClipboardStaysEmpty() async throws {
        pasteboard.clearContents()

        try await makePaste(KeystrokeProbe()).paste("dictated")

        #expect(pasteboard.string(forType: .string) == nil)
    }

    @Test("something the user copies before the restore is kept, not overwritten")
    func newerCopyIsNotOverwritten() async throws {
        pasteboard.clearContents()
        pasteboard.setString("original", forType: .string)
        let probe = KeystrokeProbe()
        probe.copyDuringPaste = "copied meanwhile"

        try await makePaste(probe).paste("dictated")

        #expect(pasteboard.string(forType: .string) == "copied meanwhile")
    }

    @Test("a failed keystroke restores the clipboard and rethrows")
    func keystrokeFailureRestores() async {
        pasteboard.clearContents()
        pasteboard.setString("original", forType: .string)
        let probe = KeystrokeProbe()
        probe.error = .keystrokeFailed

        await #expect(throws: PasteError.keystrokeFailed) {
            try await makePaste(probe).paste("dictated")
        }
        #expect(pasteboard.string(forType: .string) == "original")
    }
}
