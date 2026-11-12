import ApplicationServices

/// Thin seam over the macOS Accessibility (AX) calls used for insertion. Real: `SystemAccessibility`.
///
/// Only element metadata (subrole, role of ancestors, settability) is read. Text values of other apps are never read.
@MainActor
protocol AccessibilityAPI: AnyObject {
    associatedtype Element

    /// Whether this process is trusted for Accessibility. Never shows a prompt.
    func isProcessTrusted() -> Bool
    /// Asks macOS to show its Accessibility prompt (it links to System Settings).
    func requestTrust()
    func focusedElement(ofApplication processIdentifier: pid_t) throws(AXCallError) -> Element
    func subrole(of element: Element) -> String?
    /// Whether the element sits inside web content (an `AXWebArea` ancestor): browsers and
    /// Electron/Chromium apps, whose editors often ignore or silently drop an AX selected-text set.
    func isInWebContent(_ element: Element) -> Bool
    func isSelectedTextSettable(_ element: Element) throws(AXCallError) -> Bool
    /// Replaces the element's selection (or inserts at the caret when nothing is selected).
    func setSelectedText(_ text: String, on element: Element) throws(AXCallError)
}

/// A failed AX call, carrying the raw `AXError`.
struct AXCallError: Error, Equatable {
    let code: AXError
}
