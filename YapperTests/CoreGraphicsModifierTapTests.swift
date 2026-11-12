import Testing

@testable import Yapper

/// The real adapter, exercised only along paths that never create an event tap. Installing a tap needs
/// Input Monitoring and watches the real keyboard, so `start` is verified manually (see PLAN.md).
@MainActor
@Suite("CoreGraphicsModifierTap")
struct CoreGraphicsModifierTapTests {
    @Test("constructing and stopping the real tap never installs anything")
    func constructionIsInert() {
        let tap = CoreGraphicsModifierTap()

        #expect(!tap.isInstalled)
        tap.stop()
        #expect(!tap.isInstalled)
    }

    @Test("re-enabling without an installed tap reports failure instead of creating one")
    func reenableWithoutTapFails() {
        let tap = CoreGraphicsModifierTap()

        #expect(!tap.reenable())
        #expect(!tap.isInstalled)
    }
}
