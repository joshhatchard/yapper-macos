import ApplicationServices

/// `AccessibilityAPI` backed by `AXUIElement`. Requires the app to be trusted in
/// System Settings > Privacy & Security > Accessibility; otherwise calls fail with `.apiDisabled`.
///
/// Calls are synchronous IPC to the target app on the main actor. Each element gets a short
/// messaging timeout so a hung target fails with `.cannotComplete` instead of blocking for the
/// system default (about 6 s).
@MainActor
final class SystemAccessibility: AccessibilityAPI {
    static let messagingTimeout: Float = 1
    static let maxAncestorDepth = 64
    static let webAreaRole = "AXWebArea"

    func isProcessTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system Accessibility prompt if untrusted. Prompting is asynchronous.
    func requestTrust() {
        // Literal value of `kAXTrustedCheckOptionPrompt` (a mutable C global, not concurrency-safe in Swift 6).
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func focusedElement(ofApplication processIdentifier: pid_t) throws(AXCallError) -> AXUIElement {
        let application = AXUIElementCreateApplication(processIdentifier)
        AXUIElementSetMessagingTimeout(application, Self.messagingTimeout)
        var value: CFTypeRef?
        let code = AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute as CFString, &value)
        guard code == .success else { throw AXCallError(code: code) }
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { throw AXCallError(code: .noValue) }
        let element = unsafeDowncast(value, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(element, Self.messagingTimeout)
        return element
    }

    func subrole(of element: AXUIElement) -> String? {
        stringAttribute(kAXSubroleAttribute, of: element)
    }

    /// Walks `AXParent` up to `maxAncestorDepth` levels looking for an `AXWebArea` role.
    func isInWebContent(_ element: AXUIElement) -> Bool {
        var current: AXUIElement? = element
        for _ in 0..<Self.maxAncestorDepth {
            guard let node = current else { return false }
            AXUIElementSetMessagingTimeout(node, Self.messagingTimeout)
            if stringAttribute(kAXRoleAttribute, of: node) == Self.webAreaRole { return true }
            current = parent(of: node)
        }
        return false
    }

    func isSelectedTextSettable(_ element: AXUIElement) throws(AXCallError) -> Bool {
        var settable: DarwinBoolean = false
        let code = AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable)
        guard code == .success else { throw AXCallError(code: code) }
        return settable.boolValue
    }

    func setSelectedText(_ text: String, on element: AXUIElement) throws(AXCallError) {
        let code = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString)
        guard code == .success else { throw AXCallError(code: code) }
    }

    private func stringAttribute(_ attribute: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private func parent(of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &value) == .success,
            let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }
}
