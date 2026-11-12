import Foundation
import Testing

@testable import Yapper

/// Integration checks against this test process only; no other app is inspected.
@MainActor
@Suite("SystemWorkspace")
struct SystemWorkspaceTests {
    let workspace = SystemWorkspace()

    @Test("own process identifier is this process")
    func ownProcessIdentifier() {
        #expect(workspace.ownProcessIdentifier == ProcessInfo.processInfo.processIdentifier)
    }

    @Test("this process is running")
    func ownProcessIsRunning() {
        #expect(workspace.isRunning(ProcessInfo.processInfo.processIdentifier))
    }

    @Test("an unused process identifier is not running")
    func unusedIdentifierIsNotRunning() {
        #expect(!workspace.isRunning(-1))
        #expect(!workspace.isRunning(Int32.max))
    }
}
